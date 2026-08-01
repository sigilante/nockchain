//! The driver itself: intent in, outcome out.
//!
//! This module owns the pipeline and nothing else. Every stage it calls lives
//! behind a trait or in a sibling module, so the ordering rules — which are the
//! actual product here — are readable in one place:
//!
//! ```text
//!  validate -> journal.accept -> read balance -> classify -> plan
//!    -> journal.planned -> sign -> validate signature -> journal.signed
//!    -> submit -> journal.submitted -> [confirm] -> journal.confirmed
//! ```
//!
//! Two orderings carry the correctness of the whole thing:
//!
//! - **`journal.signed` happens before `submit`.** If the process dies during
//!   submission, recovery finds signed bytes and resubmits exactly those. If
//!   the order were reversed, a crash between submitting and journalling would
//!   leave a live transaction the driver had no record of, and the next run
//!   would plan a second one against the same notes.
//! - **`journal.submitted` happens after the node accepts.** It is a record of
//!   fact, not of intent; recovery treats `Signed` and `Submitted` identically
//!   anyway (both resubmit), so nothing depends on it being written promptly.

use std::sync::Arc;
use std::time::Duration;

use nockchain_types::tx_engine::common::BlockHeight;
use tokio::sync::{broadcast, Mutex};

use crate::build::{plan, TxPlan};
use crate::chain::{ChainSource, SubmitStatus};
use crate::error::{RejectReason, Result, TxDriverError};
use crate::intent::{IntentId, TxIntent, TxOutcome};
use crate::journal::{cue_raw_tx, IntentState, Journal};
use crate::notes::{classify, ClassifiedNotes, SpendConditionMatcher, UnlockContext};
use crate::sign::{validate_signed, ChainState, SignError, SignRequest, Signer};

/// How hard the driver tries to see a transaction land in a block.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfirmPolicy {
    /// Return as soon as the node accepts the transaction into its mempool.
    /// The caller is responsible for tracking confirmation.
    NoWait,
    /// Poll until the transaction appears in a block or the budget runs out.
    /// Running out is reported as [`TxOutcome::Submitted`], never as a failure:
    /// a transaction that has not confirmed *yet* has not failed.
    Poll { interval: Duration, attempts: u32 },
}

impl Default for ConfirmPolicy {
    fn default() -> Self {
        Self::Poll {
            interval: Duration::from_secs(5),
            attempts: 60,
        }
    }
}

/// Driver configuration. A plain struct with a `Default`: no clap, no `argv`.
///
/// The crate this replaces exported a clap `Parser` and called `Args::parse()`
/// on the host binary's own command line, so an app with any flags of its own
/// could not use it. Any CLI layer belongs in a consumer binary, built from
/// these fields.
#[derive(Debug, Clone)]
pub struct TxDriverConfig {
    /// Directory for the durable journal.
    pub journal_dir: std::path::PathBuf,
    /// Build and sign, but never submit. Dry-run intents are deliberately not
    /// journalled, so they cannot be resurrected by a later recovery.
    pub dry_run: bool,
    /// Confirmation tracking policy.
    pub confirm: ConfirmPolicy,
    /// Relative timelock, in blocks, that marks a lock as coinbase-style.
    pub coinbase_relative_min: Option<u64>,
    /// Capacity of the outcome broadcast channel.
    pub outcome_buffer: usize,
}

impl Default for TxDriverConfig {
    fn default() -> Self {
        Self {
            journal_dir: std::path::PathBuf::from("tx-driver"),
            dry_run: false,
            confirm: ConfirmPolicy::default(),
            coinbase_relative_min: None,
            outcome_buffer: 256,
        }
    }
}

/// Turns intents into confirmed transactions.
pub struct TxDriver {
    config: TxDriverConfig,
    chain: Arc<dyn ChainSource>,
    signer: Arc<dyn Signer>,
    journal: Mutex<Journal>,
    outcomes: broadcast::Sender<Arc<TxOutcome>>,
}

impl TxDriver {
    /// Opens the journal and builds a driver. Does not itself recover — call
    /// [`TxDriver::recover`] to resume interrupted work, so that a host can
    /// decide when (and whether) that happens.
    pub async fn new(
        config: TxDriverConfig,
        chain: Arc<dyn ChainSource>,
        signer: Arc<dyn Signer>,
    ) -> Result<Self> {
        let journal = Journal::open(&config.journal_dir).await?;
        let (outcomes, _) = broadcast::channel(config.outcome_buffer.max(1));
        Ok(Self {
            config,
            chain,
            signer,
            journal: Mutex::new(journal),
            outcomes,
        })
    }

    /// Subscribes to outcomes. Every intent the driver finishes is published
    /// here as well as returned from [`TxDriver::submit`], so a host can watch
    /// recovery results it never called `submit` for.
    pub fn subscribe(&self) -> broadcast::Receiver<Arc<TxOutcome>> {
        self.outcomes.subscribe()
    }

    pub fn config(&self) -> &TxDriverConfig {
        &self.config
    }

    /// Runs one intent end to end.
    ///
    /// Returns `Err` only when the driver could not reach a verdict at all;
    /// every verdict it *can* reach, including rejection, comes back as an
    /// `Ok(TxOutcome)`.
    pub async fn submit(&self, intent: TxIntent) -> Result<TxOutcome> {
        let id = intent.id;
        let outcome = match self.run(intent).await {
            Ok(outcome) => outcome,
            Err(error) => TxOutcome::Failed { id, error },
        };
        self.publish(&outcome);
        Ok(outcome)
    }

    /// Resumes every intent left unfinished by a previous run.
    ///
    /// Intents that already have signed bytes are resubmitted verbatim — never
    /// re-planned, never re-signed. Intents that do not are abandoned rather
    /// than re-planned here, because the driver no longer holds the original
    /// intent: only the caller can decide whether an unsigned request is still
    /// wanted after a restart. They are reported so the caller can decide.
    pub async fn recover(&self) -> Result<Vec<TxOutcome>> {
        let unfinished = {
            let journal = self.journal.lock().await;
            journal.unfinished()
        };

        let mut outcomes = Vec::with_capacity(unfinished.len());
        for (id, state) in unfinished {
            let outcome = match state.signed_bytes() {
                Some((tx_id, bytes)) => {
                    let tx_id = tx_id.clone();
                    match cue_raw_tx(bytes) {
                        Ok(raw_tx) => match self.submit_signed(id, &raw_tx).await {
                            Ok(outcome) => outcome,
                            Err(error) => TxOutcome::Failed { id, error },
                        },
                        Err(message) => {
                            // Undecodable signed bytes are not recoverable and
                            // not safe to re-plan around: the transaction may
                            // well be live on the network.
                            tracing::error!(
                                intent = %id,
                                tx = %tx_id.to_base58(),
                                "journalled signed transaction did not decode: {message}"
                            );
                            TxOutcome::Failed {
                                id,
                                error: TxDriverError::Noun(message),
                            }
                        }
                    }
                }
                None => {
                    let reason = format!(
                        "intent was interrupted at the {} stage before signing; nothing was \
                         submitted, so it is safe to reissue",
                        match state {
                            IntentState::Accepted => "accept",
                            _ => "plan",
                        }
                    );
                    let mut journal = self.journal.lock().await;
                    journal.rejected(id, reason.clone()).await?;
                    TxOutcome::Rejected {
                        id,
                        reason: RejectReason::PlanRejected {
                            message: reason,
                            debug_trace: Vec::new(),
                        },
                        debug_trace: Vec::new(),
                    }
                }
            };
            self.publish(&outcome);
            outcomes.push(outcome);
        }
        Ok(outcomes)
    }

    /// Drops terminal intents from the journal.
    pub async fn compact(&self) -> Result<usize> {
        let mut journal = self.journal.lock().await;
        Ok(journal.compact().await?)
    }

    /// Reads the balance for an intent's declared locks and classifies it.
    ///
    /// Exposed so a caller can show a user why a payment would be rejected
    /// before issuing it — including the value that is present but locked.
    pub async fn inspect(&self, intent: &TxIntent) -> Result<ClassifiedNotes> {
        let context = self.unlock_context().await?;
        let (matcher, _) = SpendConditionMatcher::new(intent.from.iter().cloned());
        let snapshot = self.chain.balance(&matcher.first_names()).await?;
        Ok(classify(&snapshot, &matcher, &context))
    }

    async fn run(&self, intent: TxIntent) -> Result<TxOutcome> {
        let id = intent.id;

        if let Err(reason) = intent.validate() {
            return Ok(self.reject(id, reason, Vec::new()).await);
        }

        let (matcher, rejected_conditions) =
            SpendConditionMatcher::new(intent.from.iter().cloned());
        if let Some((_, message)) = rejected_conditions.first() {
            return Ok(self
                .reject(
                    id,
                    RejectReason::MalformedIntent(format!(
                        "a source spend condition could not be hashed: {message}"
                    )),
                    Vec::new(),
                )
                .await);
        }
        if matcher.is_empty() {
            return Ok(self
                .reject(
                    id,
                    RejectReason::MalformedIntent("intent declared no usable source locks".into()),
                    Vec::new(),
                )
                .await);
        }

        // Only journal once the intent is structurally sound; a malformed
        // request should not leave a permanent trace to be recovered.
        if !self.config.dry_run {
            let mut journal = self.journal.lock().await;
            journal.accept(id).await?;
        }

        let context = self.unlock_context().await?;
        let snapshot = self.chain.balance(&matcher.first_names()).await?;
        let classified = classify(&snapshot, &matcher, &context);
        let chain_context = self.chain.chain_context().await?;

        if let Some(deadline) = &intent.deadline {
            if chain_context.height.0 .0 > deadline.0 .0 {
                return Ok(self
                    .reject(
                        id,
                        RejectReason::DeadlineExpired {
                            deadline: deadline.clone(),
                            current: chain_context.height.clone(),
                        },
                        Vec::new(),
                    )
                    .await);
            }
        }

        let plan = match plan(&intent, &classified, &matcher, &context, &chain_context) {
            Ok(plan) => plan,
            Err(reason) => {
                // Insufficient funds is the one rejection worth enriching: the
                // caller usually wants to know that the money is *there* but
                // locked, which is precisely what the old driver's silent skip
                // made impossible to tell.
                let trace = describe_blocked(&classified, &snapshot);
                return Ok(self.reject(id, reason, trace).await);
            }
        };

        if !self.config.dry_run {
            let mut journal = self.journal.lock().await;
            journal.planned(id).await?;
        }

        let signed = match self.sign(id, &plan, &classified, &snapshot).await {
            Ok(signed) => signed,
            Err(outcome) => return Ok(outcome),
        };

        let tx_id = match validate_signed(&plan, &signed) {
            Ok(tx_id) => tx_id,
            Err(reason) => return Ok(self.reject(id, reason, plan.debug_trace.clone()).await),
        };

        if self.config.dry_run {
            tracing::info!(
                intent = %id,
                tx = %tx_id.to_base58(),
                "dry run: transaction signed and validated but not submitted"
            );
            return Ok(TxOutcome::SignedNotSubmitted { id, tx_id });
        }

        {
            // The durability barrier. After this the driver is committed to
            // these exact bytes.
            let mut journal = self.journal.lock().await;
            journal.signed(id, &signed).await?;
        }

        self.submit_signed(id, &signed).await
    }

    /// Submits already-signed bytes and tracks the result. Shared by the
    /// first-run path and by recovery, so both behave identically.
    async fn submit_signed(
        &self,
        id: IntentId,
        signed: &nockchain_types::tx_engine::v1::RawTx,
    ) -> Result<TxOutcome> {
        let tx_id = signed.id.clone();

        match self.chain.submit(signed).await? {
            SubmitStatus::Accepted => {}
            SubmitStatus::Refused(message) => {
                return Ok(self
                    .reject(id, RejectReason::NetworkRefused(message), Vec::new())
                    .await);
            }
        }

        {
            let mut journal = self.journal.lock().await;
            journal.submitted(id, &tx_id).await?;
        }

        match self.config.confirm {
            ConfirmPolicy::NoWait => Ok(TxOutcome::Submitted { id, tx_id }),
            ConfirmPolicy::Poll { interval, attempts } => {
                match self.await_confirmation(&tx_id, interval, attempts).await? {
                    Some(height) => {
                        let mut journal = self.journal.lock().await;
                        journal.confirmed(id, &tx_id, &height).await?;
                        Ok(TxOutcome::Confirmed { id, tx_id, height })
                    }
                    // Not confirmed within budget is not a failure. The intent
                    // stays journalled as `Submitted`, so a later recovery
                    // resubmits the same bytes if it is still not in a block.
                    None => Ok(TxOutcome::Submitted { id, tx_id }),
                }
            }
        }
    }

    async fn await_confirmation(
        &self,
        tx_id: &nockchain_types::tx_engine::common::TxId,
        interval: Duration,
        attempts: u32,
    ) -> Result<Option<BlockHeight>> {
        for _ in 0..attempts {
            if let Some(height) = self.chain.confirmed_at(tx_id).await? {
                return Ok(Some(height));
            }
            tokio::time::sleep(interval).await;
        }
        Ok(None)
    }

    async fn sign(
        &self,
        id: IntentId,
        plan: &TxPlan,
        classified: &ClassifiedNotes,
        snapshot: &crate::chain::BalanceSnapshot,
    ) -> std::result::Result<nockchain_types::tx_engine::v1::RawTx, TxOutcome> {
        let is_input = |name: &nockchain_types::tx_engine::common::Name| {
            plan.assembled
                .inputs
                .iter()
                .any(|input| &input.note.name == name)
        };

        // Hand the signer the notes it is actually spending, not the whole
        // wallet: an approval prompt should show the inputs of this
        // transaction.
        let spent: Vec<_> = classified
            .spendable
            .iter()
            .filter(|candidate| is_input(&candidate.identity().name))
            .cloned()
            .collect();
        // The same notes as the chain reported them. A signer driving a wallet
        // kernel has to seed that kernel's balance, and the planner's
        // `CandidateNote` projection is not enough to rebuild a note from.
        let spent_notes: Vec<_> = snapshot
            .notes
            .iter()
            .filter(|(name, _)| is_input(name))
            .cloned()
            .collect();

        let chain_state = ChainState {
            height: snapshot.height.clone(),
            block_id: snapshot.block_id.clone(),
        };
        let request = SignRequest::new(id, plan.clone(), spent, chain_state, spent_notes);
        match self.signer.sign(request).await {
            Ok(signed) => Ok(signed),
            Err(err) if err.is_terminal() => {
                let reason = match err {
                    SignError::Declined(message) | SignError::NoSuchKey(message) => {
                        RejectReason::SignerDeclined(message)
                    }
                    other => RejectReason::SignerMismatch(other.to_string()),
                };
                Err(self.reject(id, reason, plan.debug_trace.clone()).await)
            }
            Err(err) => Err(TxOutcome::Failed {
                id,
                error: TxDriverError::Signer(err.to_string()),
            }),
        }
    }

    async fn unlock_context(&self) -> Result<UnlockContext> {
        let pkhs = self
            .signer
            .signer_pkhs()
            .await
            .map_err(|err| TxDriverError::Signer(err.to_string()))?;
        let mut context = UnlockContext::new().with_signer_pkhs(pkhs);
        if let Some(min) = self.config.coinbase_relative_min {
            context = context.with_coinbase_relative_min(min);
        }
        Ok(context)
    }

    /// Records a terminal rejection and builds the outcome.
    ///
    /// Journalling a rejection matters even though nothing was submitted: it
    /// stops recovery from seeing a half-finished intent and reporting it a
    /// second time.
    async fn reject(
        &self,
        id: IntentId,
        reason: RejectReason,
        debug_trace: Vec<String>,
    ) -> TxOutcome {
        if !self.config.dry_run {
            let mut journal = self.journal.lock().await;
            // A journal failure here must not mask the rejection the caller
            // needs to see, so it is logged rather than propagated.
            if let Err(err) = journal.rejected(id, reason.to_string()).await {
                tracing::warn!(intent = %id, "failed to journal rejection: {err}");
            }
        }
        TxOutcome::Rejected {
            id,
            reason,
            debug_trace,
        }
    }

    fn publish(&self, outcome: &TxOutcome) {
        // A send error just means nobody is subscribed.
        let _ = self.outcomes.send(Arc::new(clone_outcome(outcome)));
    }
}

/// Summarises unreachable value as trace lines attached to a rejection.
fn describe_blocked(
    classified: &ClassifiedNotes,
    snapshot: &crate::chain::BalanceSnapshot,
) -> Vec<String> {
    let blocked = classified.blocked_total(snapshot);
    let mut trace = vec![format!(
        "spendable: {} nicks across {} note(s)",
        classified.spendable_total(),
        classified.spendable.len()
    )];
    if blocked.pending_timelock > 0 {
        trace.push(format!(
            "{} nicks are timelocked and will become spendable on their own",
            blocked.pending_timelock
        ));
    }
    if blocked.needs_context > 0 {
        trace.push(format!(
            "{} nicks need a key, preimage, or lock this intent did not supply",
            blocked.needs_context
        ));
    }
    if blocked.permanently_locked > 0 {
        trace.push(format!(
            "{} nicks are permanently unspendable",
            blocked.permanently_locked
        ));
    }
    for (name, reason) in classified.unspendable.iter().take(16) {
        trace.push(format!("note {}: {reason}", name.first.to_base58()));
    }
    if classified.unspendable.len() > 16 {
        trace.push(format!(
            "... and {} more unspendable note(s)",
            classified.unspendable.len() - 16
        ));
    }
    trace
}

/// `TxOutcome` cannot derive `Clone` because `TxDriverError` wraps
/// non-cloneable io errors, so broadcast copies flatten the error to its
/// message. Callers that need the structured error use the value returned from
/// `submit`; subscribers get the report.
fn clone_outcome(outcome: &TxOutcome) -> TxOutcome {
    match outcome {
        TxOutcome::Confirmed { id, tx_id, height } => TxOutcome::Confirmed {
            id: *id,
            tx_id: tx_id.clone(),
            height: height.clone(),
        },
        TxOutcome::Submitted { id, tx_id } => TxOutcome::Submitted {
            id: *id,
            tx_id: tx_id.clone(),
        },
        TxOutcome::SignedNotSubmitted { id, tx_id } => TxOutcome::SignedNotSubmitted {
            id: *id,
            tx_id: tx_id.clone(),
        },
        TxOutcome::Rejected {
            id,
            reason,
            debug_trace,
        } => TxOutcome::Rejected {
            id: *id,
            reason: reason.clone(),
            debug_trace: debug_trace.clone(),
        },
        TxOutcome::Failed { id, error } => TxOutcome::Failed {
            id: *id,
            error: TxDriverError::Chain(error.to_string()),
        },
    }
}

#[cfg(test)]
mod tests {
    use std::time::Duration;

    use nockchain_types::tx_engine::v1::tx::SpendCondition;

    use super::*;
    use crate::intent::{FeePolicy, NoteSelection, Recipient};
    use crate::journal::{cue_raw_tx, jam_raw_tx, Journal};
    use crate::testing::{hash, note_for, MockChainSource, MockSigner, SignerBehaviour};

    const KEY: u64 = 1;
    const PAYEE: u64 = 500;

    fn my_lock() -> SpendCondition {
        SpendCondition::simple_pkh(hash(KEY))
    }

    fn config(dir: &std::path::Path) -> TxDriverConfig {
        TxDriverConfig {
            journal_dir: dir.to_path_buf(),
            dry_run: false,
            // Zero-interval polling keeps tests fast; the mock chain confirms
            // on the first poll.
            confirm: ConfirmPolicy::Poll {
                interval: Duration::from_millis(0),
                attempts: 3,
            },
            coinbase_relative_min: None,
            outcome_buffer: 16,
        }
    }

    fn intent(amount: u64) -> TxIntent {
        TxIntent {
            id: IntentId::from_u128(1),
            from: vec![my_lock()],
            recipients: vec![Recipient::to_pkh(hash(PAYEE), amount)],
            refund_to: None,
            fee: FeePolicy::Auto,
            note_selection: NoteSelection::Auto,
            deadline: None,
        }
    }

    /// A chain holding one note of `assets` nicks locked to our key.
    fn chain(assets: u64) -> MockChainSource {
        MockChainSource::new(1000, vec![note_for(&my_lock(), 100, 1, assets)])
    }

    async fn driver_with(
        dir: &std::path::Path,
        chain: MockChainSource,
        signer: MockSigner,
    ) -> (TxDriver, std::sync::Arc<Mutex<crate::testing::ChainLog>>) {
        let log = chain.log();
        let driver = TxDriver::new(config(dir), Arc::new(chain), Arc::new(signer))
            .await
            .expect("driver opens");
        (driver, log)
    }

    #[tokio::test]
    async fn a_payment_is_planned_signed_submitted_and_confirmed() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        match outcome {
            TxOutcome::Confirmed { id, height, .. } => {
                assert_eq!(id, IntentId::from_u128(1));
                assert_eq!(height.0 .0, 1001);
            }
            other => panic!("expected Confirmed, got {other:?}"),
        }
        assert_eq!(log.lock().await.submissions.len(), 1);
    }

    #[tokio::test]
    async fn the_outcome_echoes_the_correlation_id() {
        // The defect that crashed a downstream kernel: with no id on the
        // cause, a kernel with two payouts in flight cannot tell them apart.
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            MockChainSource::new(
                1000,
                vec![
                    note_for(&my_lock(), 100, 1, 1_000_000),
                    note_for(&my_lock(), 101, 1, 1_000_000),
                ],
            ),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let mut first = intent(100_000);
        first.id = IntentId::from_u128(0xaaaa);
        let mut second = intent(200_000);
        second.id = IntentId::from_u128(0xbbbb);
        second.note_selection = NoteSelection::AutoLargestFirst;

        let a = driver.submit(first).await.expect("runs");
        let b = driver.submit(second).await.expect("runs");

        assert_eq!(a.id(), IntentId::from_u128(0xaaaa));
        assert_eq!(b.id(), IntentId::from_u128(0xbbbb));
        assert_ne!(a.tx_id(), b.tx_id());
    }

    #[tokio::test]
    async fn a_dry_run_signs_but_never_submits_or_journals() {
        let dir = tempfile::tempdir().unwrap();
        let chain = chain(1_000_000);
        let log = chain.log();
        let mut config = config(dir.path());
        config.dry_run = true;
        let driver = TxDriver::new(
            config,
            Arc::new(chain),
            Arc::new(MockSigner::new(vec![hash(KEY)])),
        )
        .await
        .unwrap();

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(outcome, TxOutcome::SignedNotSubmitted { .. }));
        assert!(log.lock().await.submissions.is_empty());

        // Nothing journalled means a later real run cannot resurrect it.
        let journal = Journal::open(dir.path()).await.unwrap();
        assert!(journal.states().is_empty());
    }

    #[tokio::test]
    async fn insufficient_funds_is_terminal_and_explains_what_is_locked() {
        let dir = tempfile::tempdir().unwrap();
        // One spendable note, one timelocked note holding most of the value.
        let timelocked = SpendCondition::coinbase_pkh(hash(KEY), 5_000);
        let chain = MockChainSource::new(
            1000,
            vec![note_for(&my_lock(), 100, 1, 1_000), note_for(&timelocked, 101, 900, 10_000_000)],
        );
        let (driver, log) = driver_with(dir.path(), chain, MockSigner::new(vec![hash(KEY)])).await;

        let mut intent = intent(5_000_000);
        intent.from = vec![my_lock(), timelocked];
        let outcome = driver.submit(intent).await.expect("runs");

        match outcome {
            TxOutcome::Rejected {
                reason,
                debug_trace,
                ..
            } => {
                assert!(matches!(reason, RejectReason::InsufficientFunds { .. }));
                assert!(
                    debug_trace.iter().any(|line| line.contains("timelocked")),
                    "the caller must be told the money is present but locked, not just \
                     that funds are insufficient: {debug_trace:?}"
                );
            }
            other => panic!("expected Rejected, got {other:?}"),
        }
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn a_rejection_is_safe_to_roll_back_and_a_failure_is_not() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) =
            driver_with(dir.path(), chain(10), MockSigner::new(vec![hash(KEY)])).await;
        let rejected = driver.submit(intent(1_000_000)).await.expect("runs");
        assert!(rejected.is_safe_to_roll_back());

        let dir2 = tempfile::tempdir().unwrap();
        let (driver2, _) = driver_with(
            dir2.path(),
            chain(1_000_000).with_transport_failure(),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        let failed = driver2.submit(intent(100_000)).await.expect("runs");
        assert!(matches!(failed, TxOutcome::Failed { .. }));
        assert!(
            !failed.is_safe_to_roll_back(),
            "a transport failure leaves the spend's status unknown"
        );
    }

    #[tokio::test]
    async fn a_signer_that_redirects_funds_is_rejected_before_submission() {
        let dir = tempfile::tempdir().unwrap();
        let signer = MockSigner::new(vec![hash(KEY)]).behaving(SignerBehaviour::RedirectOutputs {
            lock_root: hash(9999),
        });
        let (driver, log) = driver_with(dir.path(), chain(1_000_000), signer).await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::SignerMismatch(_),
                ..
            }
        ));
        assert!(
            log.lock().await.submissions.is_empty(),
            "a mismatched transaction must never reach the network"
        );
    }

    #[tokio::test]
    async fn a_signer_that_inflates_the_fee_is_rejected_before_submission() {
        let dir = tempfile::tempdir().unwrap();
        let signer =
            MockSigner::new(vec![hash(KEY)]).behaving(SignerBehaviour::InflateFee { fee: 900_000 });
        let (driver, log) = driver_with(dir.path(), chain(1_000_000), signer).await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::SignerMismatch(_),
                ..
            }
        ));
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn a_signer_that_adds_an_output_is_rejected_before_submission() {
        let dir = tempfile::tempdir().unwrap();
        let signer = MockSigner::new(vec![hash(KEY)]).behaving(SignerBehaviour::AddOutput {
            lock_root: hash(9999),
            amount: 1,
        });
        let (driver, log) = driver_with(dir.path(), chain(1_000_000), signer).await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::SignerMismatch(_),
                ..
            }
        ));
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn a_declining_signer_is_a_terminal_rejection() {
        let dir = tempfile::tempdir().unwrap();
        let signer = MockSigner::new(vec![hash(KEY)])
            .behaving(SignerBehaviour::Decline("user pressed reject".into()));
        let (driver, _) = driver_with(dir.path(), chain(1_000_000), signer).await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::SignerDeclined(_),
                ..
            }
        ));
        assert!(outcome.is_safe_to_roll_back());
    }

    #[tokio::test]
    async fn an_unavailable_signer_is_a_non_terminal_failure() {
        let dir = tempfile::tempdir().unwrap();
        let signer = MockSigner::new(vec![hash(KEY)])
            .behaving(SignerBehaviour::Unavailable("socket closed".into()));
        let (driver, _) = driver_with(dir.path(), chain(1_000_000), signer).await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(outcome, TxOutcome::Failed { .. }));
        // Nothing was signed or submitted, but the driver does not claim to
        // know that, so the caller must not roll back on this signal alone.
        assert!(!outcome.is_safe_to_roll_back());
    }

    #[tokio::test]
    async fn a_network_refusal_is_terminal() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000).refusing("invalid signature"),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::NetworkRefused(_),
                ..
            }
        ));
    }

    #[tokio::test]
    async fn a_crash_after_signing_resubmits_the_identical_transaction() {
        // The exactly-once property end to end: a driver that dies during
        // submission must resubmit the same bytes, never plan a second
        // transaction against the same notes.
        let dir = tempfile::tempdir().unwrap();

        // First run: the network is unreachable, so the intent is journalled as
        // `Signed` and the driver reports a non-terminal failure.
        let first_chain = chain(1_000_000).with_transport_failure();
        let first_log = first_chain.log();
        let (driver, _) = (
            TxDriver::new(
                config(dir.path()),
                Arc::new(first_chain),
                Arc::new(MockSigner::new(vec![hash(KEY)])),
            )
            .await
            .unwrap(),
            (),
        );
        let outcome = driver.submit(intent(100_000)).await.expect("runs");
        assert!(matches!(outcome, TxOutcome::Failed { .. }));
        let attempted = first_log.lock().await.submissions.clone();
        assert_eq!(attempted.len(), 1);
        drop(driver);

        // Second run: recovery finds signed bytes and resubmits them verbatim.
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        let recovered = driver.recover().await.expect("recovers");

        assert_eq!(recovered.len(), 1);
        assert!(matches!(recovered[0], TxOutcome::Confirmed { .. }));
        let resubmitted = log.lock().await.submissions.clone();
        assert_eq!(resubmitted.len(), 1);
        assert_eq!(
            resubmitted[0], attempted[0],
            "recovery must resubmit byte-identical bytes, not a freshly planned transaction"
        );
        // And the decoded transaction id is the same one, so a caller polling
        // on the original id still sees it land.
        assert_eq!(
            cue_raw_tx(&resubmitted[0]).unwrap().id,
            cue_raw_tx(&attempted[0]).unwrap().id
        );
    }

    #[tokio::test]
    async fn recovery_is_idempotent_across_repeated_restarts() {
        let dir = tempfile::tempdir().unwrap();
        let first_chain = chain(1_000_000).with_transport_failure();
        let driver = TxDriver::new(
            config(dir.path()),
            Arc::new(first_chain),
            Arc::new(MockSigner::new(vec![hash(KEY)])),
        )
        .await
        .unwrap();
        driver.submit(intent(100_000)).await.expect("runs");
        drop(driver);

        // Recover twice against a chain that never confirms, then once against
        // one that does. The transaction must stay the same throughout.
        let mut all: Vec<Vec<u8>> = Vec::new();
        for _ in 0..2 {
            let (driver, log) = driver_with(
                dir.path(),
                chain(1_000_000).never_confirming(),
                MockSigner::new(vec![hash(KEY)]),
            )
            .await;
            let outcomes = driver.recover().await.expect("recovers");
            assert!(matches!(outcomes[0], TxOutcome::Submitted { .. }));
            all.extend(log.lock().await.submissions.clone());
        }
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        driver.recover().await.expect("recovers");
        all.extend(log.lock().await.submissions.clone());

        assert_eq!(all.len(), 3);
        assert!(
            all.windows(2).all(|w| w[0] == w[1]),
            "every resubmission must be byte-identical"
        );

        // Once confirmed, there is nothing left to recover.
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        assert!(driver.recover().await.expect("recovers").is_empty());
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn an_intent_interrupted_before_signing_is_reported_not_replanned() {
        // Nothing was shown to the network, so re-planning would be safe — but
        // the driver no longer has the intent, and inventing one would be
        // worse than telling the caller to reissue.
        let dir = tempfile::tempdir().unwrap();
        let id = IntentId::from_u128(77);
        {
            let mut journal = Journal::open(dir.path()).await.unwrap();
            journal.accept(id).await.unwrap();
            journal.planned(id).await.unwrap();
        }

        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        let recovered = driver.recover().await.expect("recovers");

        assert_eq!(recovered.len(), 1);
        assert_eq!(recovered[0].id(), id);
        assert!(recovered[0].is_safe_to_roll_back());
        assert!(log.lock().await.submissions.is_empty());

        // Reported once and then closed out, so a second restart is quiet.
        drop(driver);
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        assert!(driver.recover().await.expect("recovers").is_empty());
    }

    #[tokio::test]
    async fn an_expired_deadline_rejects_before_anything_is_signed() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let mut intent = intent(100_000);
        intent.deadline = Some(BlockHeight(nockchain_math::belt::Belt(999)));
        let outcome = driver.submit(intent).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::DeadlineExpired { .. },
                ..
            }
        ));
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn the_signer_sees_only_the_notes_being_spent() {
        let dir = tempfile::tempdir().unwrap();
        let signer = MockSigner::new(vec![hash(KEY)]);
        let calls = signer.calls();
        let chain = MockChainSource::new(
            1000,
            vec![
                note_for(&my_lock(), 100, 1, 500_000),
                note_for(&my_lock(), 101, 1, 500_000),
                note_for(&my_lock(), 102, 1, 500_000),
            ],
        );
        let (driver, _) = driver_with(dir.path(), chain, signer).await;

        driver.submit(intent(100_000)).await.expect("runs");

        let calls = calls.lock().await;
        let request = calls.first().expect("the signer was called");
        assert_eq!(
            request.notes.len(),
            request.plan.assembled.inputs.len(),
            "an approval prompt should show this transaction's inputs, not the whole wallet"
        );
        assert!(!request.spend_conditions.is_empty());
        assert_eq!(request.intent_id, IntentId::from_u128(1));
    }

    #[tokio::test]
    async fn inspect_reports_locked_value_without_moving_anything() {
        let dir = tempfile::tempdir().unwrap();
        let timelocked = SpendCondition::coinbase_pkh(hash(KEY), 5_000);
        let chain = MockChainSource::new(
            1000,
            vec![note_for(&my_lock(), 100, 1, 1_000), note_for(&timelocked, 101, 900, 10_000)],
        );
        let (driver, log) = driver_with(dir.path(), chain, MockSigner::new(vec![hash(KEY)])).await;

        let mut intent = intent(100);
        intent.from = vec![my_lock(), timelocked];
        let classified = driver.inspect(&intent).await.expect("inspects");

        assert_eq!(classified.spendable_total(), 1_000);
        assert_eq!(classified.unspendable.len(), 1);
        assert!(log.lock().await.submissions.is_empty());
    }

    #[tokio::test]
    async fn outcomes_are_published_to_subscribers() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        let mut subscriber = driver.subscribe();

        driver.submit(intent(100_000)).await.expect("runs");

        let published = subscriber.try_recv().expect("an outcome was published");
        assert_eq!(published.id(), IntentId::from_u128(1));
        assert!(matches!(*published, TxOutcome::Confirmed { .. }));
    }

    #[tokio::test]
    async fn a_transaction_that_never_confirms_stays_submitted_not_failed() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000).never_confirming(),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let outcome = driver.submit(intent(100_000)).await.expect("runs");

        assert!(
            matches!(outcome, TxOutcome::Submitted { .. }),
            "a transaction still in the mempool has not failed"
        );
        assert!(!outcome.is_safe_to_roll_back());
    }

    #[tokio::test]
    async fn compaction_leaves_live_intents_recoverable() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        driver.submit(intent(100_000)).await.expect("runs");
        assert_eq!(driver.compact().await.expect("compacts"), 1);
        drop(driver);

        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        assert!(driver.recover().await.expect("recovers").is_empty());
    }

    #[tokio::test]
    async fn a_malformed_intent_leaves_no_journal_trace() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, _) = driver_with(
            dir.path(),
            chain(1_000_000),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;

        let mut bad = intent(100_000);
        bad.recipients.clear();
        let outcome = driver.submit(bad).await.expect("runs");

        assert!(matches!(
            outcome,
            TxOutcome::Rejected {
                reason: RejectReason::MalformedIntent(_),
                ..
            }
        ));
        drop(driver);
        let journal = Journal::open(dir.path()).await.unwrap();
        assert!(
            journal.states().is_empty(),
            "a structurally invalid request should not be recorded"
        );
    }

    #[tokio::test]
    async fn the_journalled_bytes_decode_to_the_submitted_transaction() {
        let dir = tempfile::tempdir().unwrap();
        let (driver, log) = driver_with(
            dir.path(),
            chain(1_000_000).never_confirming(),
            MockSigner::new(vec![hash(KEY)]),
        )
        .await;
        driver.submit(intent(100_000)).await.expect("runs");
        let submitted = log.lock().await.submissions[0].clone();
        drop(driver);

        let journal = Journal::open(dir.path()).await.unwrap();
        let state = journal.state(&IntentId::from_u128(1)).expect("journalled");
        let (tx_id, bytes) = state.signed_bytes().expect("has signed bytes");
        assert_eq!(bytes, submitted.as_slice());
        assert_eq!(jam_raw_tx(&cue_raw_tx(bytes).unwrap()), submitted);
        assert_eq!(*tx_id, cue_raw_tx(&submitted).unwrap().id);
    }
}
