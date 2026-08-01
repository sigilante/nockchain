//! Turning an intent into a concrete, priced transaction plan.
//!
//! This stage owns no policy of its own. Note selection, the two-pass fee
//! estimate, timelock admission, and conservation checking all live in
//! [`wallet_tx_builder::planner`], which is the same code the wallet CLI uses;
//! reimplementing any of it here would mean the driver and the wallet could
//! disagree about what a transaction costs. What this module does is translate
//! between the driver's vocabulary ([`TxIntent`], [`SpendCondition`]) and the
//! planner's ([`PlanRequest`], lock roots), enforce the caller's
//! [`FeePolicy`], and turn planner failures into the terminal/non-terminal
//! split the outcome contract promises.

use nockchain_types::tx_engine::common::Hash;
use nockchain_types::tx_engine::v1::tx::SpendCondition;
use wallet_tx_builder::planner::{plan_create_tx, PlanError};
use wallet_tx_builder::types::{
    AssembledInput, AssembledOutput, AssembledTransaction, CandidateVersionPolicy, ChainContext,
    CreateTxPlanningMode, PlanRequest, PlanResult, PlannedOutput, SelectionMode, SelectionOrder,
};

use crate::error::RejectReason;
use crate::intent::{FeePolicy, NoteSelection, TxIntent};
use crate::notes::{ClassifiedNotes, SpendConditionMatcher, UnlockContext};

/// A priced, input-selected transaction, ready to be signed.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TxPlan {
    /// Inputs paired with the spend condition that unlocks each, and outputs
    /// with their final amounts. This is what the signer must reproduce
    /// exactly; anything else it returns is a [`RejectReason::SignerMismatch`].
    pub assembled: AssembledTransaction,
    /// The spend conditions referenced by `assembled.inputs`, deduplicated.
    /// Handed to the signer so it can render an approval prompt from data it
    /// can verify itself rather than trusting a summary.
    pub spend_conditions: Vec<SpendCondition>,
    /// The planner's own decision log. Carried through to the outcome because
    /// a selection failure is otherwise almost impossible to debug from
    /// outside.
    pub debug_trace: Vec<String>,
}

impl TxPlan {
    /// Total value paid to non-refund outputs plus the fee.
    pub fn total_spent(&self) -> u64 {
        self.assembled
            .outputs
            .iter()
            .map(|o| o.amount)
            .fold(0u64, |acc, v| acc.saturating_add(v))
            .saturating_add(self.assembled.fee)
    }

    pub fn fee(&self) -> u64 {
        self.assembled.fee
    }

    pub fn input_count(&self) -> usize {
        self.assembled.inputs.len()
    }
}

/// Builds a plan for `intent` against a classified balance snapshot.
///
/// Returns a [`RejectReason`] rather than an error type on failure: every way
/// this stage can fail is terminal, because it happens strictly before any
/// transaction reaches the network and re-running it against the same snapshot
/// deterministically produces the same answer.
pub fn plan(
    intent: &TxIntent,
    classified: &ClassifiedNotes,
    matcher: &SpendConditionMatcher,
    context: &UnlockContext,
    chain: &ChainContext,
) -> std::result::Result<TxPlan, RejectReason> {
    intent.validate()?;

    let refund_lock = intent.refund_lock().ok_or_else(|| {
        RejectReason::MalformedIntent("intent has no refund lock and no source lock".into())
    })?;

    let recipient_outputs = intent
        .recipients
        .iter()
        .map(|recipient| {
            Ok(PlannedOutput {
                lock_root: lock_root(&recipient.lock)?,
                amount: recipient.amount_nicks,
                note_data: Vec::new(),
            })
        })
        .collect::<std::result::Result<Vec<_>, RejectReason>>()?;

    // The planner assigns the refund amount itself; `amount: 0` is its
    // "planner-owned" sentinel (see the TODO on `PlanRequest::refund_output`).
    let refund_output = PlannedOutput {
        lock_root: lock_root(refund_lock)?,
        amount: 0,
        note_data: Vec::new(),
    };

    let (selection_mode, order_direction) = match &intent.note_selection {
        NoteSelection::Auto => (SelectionMode::Auto, SelectionOrder::Ascending),
        NoteSelection::AutoLargestFirst => (SelectionMode::Auto, SelectionOrder::Descending),
        NoteSelection::Manual(names) => (
            SelectionMode::Manual {
                note_names: names.clone(),
            },
            SelectionOrder::Ascending,
        ),
    };

    let base_request = PlanRequest {
        planning_mode: CreateTxPlanningMode::Standard,
        selection_mode,
        order_direction,
        include_data: false,
        chain_context: chain.clone(),
        signer_pkh: context.primary_signer_pkh(),
        candidate_version_policy: CandidateVersionPolicy::V1Only,
        candidates: classified.spendable.clone(),
        recipient_outputs,
        refund_output,
        coinbase_relative_min: context.coinbase_relative_min(),
        v0_migration_signer_pubkeys: Vec::new(),
    };

    let result = run_planner(&base_request, matcher, classified)?;

    // Apply the fee policy. Raising the fee is done by re-running the planner
    // with a higher `min_fee` floor rather than by patching the result: the
    // refund output has to absorb the difference, and only the planner knows
    // how to re-balance conservation after that.
    let result = match intent.fee {
        FeePolicy::Auto => result,
        FeePolicy::AtLeast(floor) if floor <= result.final_fee => result,
        FeePolicy::AtLeast(floor) => {
            let request = with_min_fee(&base_request, floor);
            run_planner(&request, matcher, classified)?
        }
        FeePolicy::Exact(exact) if exact < result.final_fee => {
            return Err(RejectReason::PlanRejected {
                message: format!(
                    "requested exact fee of {exact} nicks is below the minimum viable fee of {} nicks",
                    result.final_fee
                ),
                debug_trace: result.debug_trace,
            });
        }
        FeePolicy::Exact(exact) if exact == result.final_fee => result,
        FeePolicy::Exact(exact) => {
            let request = with_min_fee(&base_request, exact);
            let raised = run_planner(&request, matcher, classified)?;
            if raised.final_fee != exact {
                // A floor of `exact` should produce exactly `exact` for a
                // transaction whose natural fee is lower. If it does not, the
                // planner's shape changed under the higher fee (more inputs
                // needed, so more words) and we cannot honour "exact".
                return Err(RejectReason::PlanRejected {
                    message: format!(
                        "cannot honour an exact fee of {exact} nicks: raising the fee changed the \
                         transaction shape and the planner settled on {} nicks",
                        raised.final_fee
                    ),
                    debug_trace: raised.debug_trace,
                });
            }
            raised
        }
    };

    assemble(result, intent, matcher)
}

/// Runs the planner and maps its errors onto the rejection taxonomy.
fn run_planner(
    request: &PlanRequest,
    matcher: &SpendConditionMatcher,
    classified: &ClassifiedNotes,
) -> std::result::Result<PlanResult, RejectReason> {
    plan_create_tx(request, matcher).map_err(|err| match err {
        PlanError::InsufficientFunds {
            selected_total,
            required,
        } => {
            // Report the total the driver could actually reach, not the
            // planner's partial selection, so the message lines up with what a
            // user sees in their wallet.
            let _ = selected_total;
            RejectReason::InsufficientFunds {
                needed: required,
                available: classified.spendable_total(),
            }
        }
        PlanError::ManualNoteMissing { first, last } => {
            RejectReason::PlanRejected {
                message: format!("manually selected note {first}/{last} is not in the balance"),
                debug_trace: Vec::new(),
            }
        }
        PlanError::UnknownLock { first, last, .. }
        | PlanError::MissingPlanningSpendCondition { first, last, .. } => {
            // The matcher admitted the note but could not produce a spend
            // condition for it. That is a driver bug rather than a user error,
            // but it is still terminal for this intent.
            let _ = matcher;
            RejectReason::PlanRejected {
                message: format!(
                    "note {first}/{last} was admitted for selection but no spend condition could \
                     be resolved for it"
                ),
                debug_trace: Vec::new(),
            }
        }
        other => RejectReason::PlanRejected {
            message: other.to_string(),
            debug_trace: Vec::new(),
        },
    })
}

/// Copies a request with a raised minimum-fee floor.
fn with_min_fee(request: &PlanRequest, min_fee: u64) -> PlanRequest {
    let mut out = request.clone();
    out.chain_context.min_fee = min_fee;
    out
}

/// Pairs each selected input with the spend condition that unlocks it.
fn assemble(
    result: PlanResult,
    intent: &TxIntent,
    matcher: &SpendConditionMatcher,
) -> std::result::Result<TxPlan, RejectReason> {
    let mut inputs = Vec::with_capacity(result.selected.len());
    let mut spend_conditions: Vec<SpendCondition> = Vec::new();

    for identity in result.selected {
        let condition = matcher
            .condition_for(&identity.name.first)
            .ok_or_else(|| RejectReason::PlanRejected {
                message: format!(
                    "planner selected note {} whose lock was never declared by the intent",
                    identity.name.first.to_base58()
                ),
                debug_trace: result.debug_trace.clone(),
            })?
            .clone();

        if !spend_conditions.contains(&condition) {
            spend_conditions.push(condition.clone());
        }
        inputs.push(AssembledInput {
            note: identity,
            lock: condition,
        });
    }

    if inputs.is_empty() {
        return Err(RejectReason::PlanRejected {
            message: "planner selected no inputs".into(),
            debug_trace: result.debug_trace,
        });
    }

    let outputs = result
        .outputs
        .into_iter()
        // The planner emits the refund output even when it is empty; a
        // zero-value output is not representable on chain, so drop it here
        // rather than making the signer deal with it.
        .filter(|output| output.amount > 0)
        .map(|output| AssembledOutput {
            lock_root: output.lock_root,
            amount: output.amount,
        })
        .collect::<Vec<_>>();

    if outputs.is_empty() {
        return Err(RejectReason::PlanRejected {
            message: "planner produced no non-zero outputs".into(),
            debug_trace: result.debug_trace,
        });
    }

    // Conservation is checked by the planner, but re-checking it here is cheap
    // and guards the translation above: a bug that dropped an input or an
    // output would otherwise produce a transaction that the network rejects
    // long after the driver reported success.
    let recipient_total = intent
        .total_recipient_amount()
        .ok_or_else(|| RejectReason::MalformedIntent("recipient amounts overflow u64".into()))?;
    let output_total = outputs
        .iter()
        .map(|o| o.amount)
        .try_fold(0u64, |acc, v| acc.checked_add(v))
        .ok_or_else(|| RejectReason::PlanRejected {
            message: "planned output amounts overflow u64".into(),
            debug_trace: result.debug_trace.clone(),
        })?;
    if output_total < recipient_total {
        return Err(RejectReason::PlanRejected {
            message: format!(
                "planned outputs total {output_total} nicks, which is less than the \
                 {recipient_total} nicks requested by recipients"
            ),
            debug_trace: result.debug_trace,
        });
    }

    Ok(TxPlan {
        assembled: AssembledTransaction {
            inputs,
            outputs,
            fee: result.final_fee,
        },
        spend_conditions,
        debug_trace: result.debug_trace,
    })
}

/// Derives the consensus lock root for a spend condition.
///
/// For a single spend condition, `Lock::SpendCondition(sc).hash()` and
/// `sc.hash()` are the same digest (`Lock`'s hashable form delegates straight
/// through for that variant), so this is the same lock root the wallet and the
/// Hoon tx-engine compute.
pub fn lock_root(condition: &SpendCondition) -> std::result::Result<Hash, RejectReason> {
    condition.hash().map_err(|err| {
        RejectReason::MalformedIntent(format!("spend condition could not be hashed: {err}"))
    })
}

#[cfg(test)]
mod tests {
    use nockchain_math::belt::Belt;
    use nockchain_types::tx_engine::common::{BlockHeight, FirstName, Name, Nicks, Version};
    use nockchain_types::tx_engine::v1;
    use nockchain_types::tx_engine::v1::note::{NoteData, NoteV1};

    use super::*;
    use crate::chain::BalanceSnapshot;
    use crate::intent::{IntentId, Recipient};
    use crate::notes::classify;

    fn hash(seed: u64) -> Hash {
        Hash([
            Belt(seed + 1),
            Belt(seed + 2),
            Belt(seed + 3),
            Belt(seed + 4),
            Belt(seed + 5),
        ])
    }

    fn height(n: u64) -> BlockHeight {
        BlockHeight(Belt(n))
    }

    fn note_for(condition: &SpendCondition, seed: u64, assets: u64) -> (Name, v1::Note) {
        let first = condition.first_name().expect("first-name derives").into_hash();
        let name = Name::new(first, hash(seed));
        let note = v1::Note::V1(NoteV1 {
            version: Version::V1,
            origin_page: height(1),
            name: name.clone(),
            note_data: NoteData(vec![]),
            assets: Nicks(assets as usize),
        });
        (name, note)
    }

    fn chain_context() -> ChainContext {
        ChainContext {
            height: height(1000),
            bythos_phase: height(0),
            base_fee: 10,
            input_fee_divisor: 2,
            min_fee: 100,
        }
    }

    /// Builds a wallet holding `note_values`, all locked to one PKH the signer
    /// controls, and returns everything `plan` needs.
    fn wallet(
        note_values: &[u64],
    ) -> (
        SpendCondition,
        ClassifiedNotes,
        SpendConditionMatcher,
        UnlockContext,
    ) {
        let key = hash(1);
        let condition = SpendCondition::simple_pkh(key.clone());
        let notes = note_values
            .iter()
            .enumerate()
            .map(|(idx, value)| note_for(&condition, 100 + idx as u64, *value))
            .collect::<Vec<_>>();
        let snapshot = BalanceSnapshot {
            height: height(1000),
            block_id: hash(7),
            notes,
        };
        let (matcher, _) = SpendConditionMatcher::new([condition.clone()]);
        let context = UnlockContext::new().with_signer_pkh(key);
        let classified = classify(&snapshot, &matcher, &context);
        (condition, classified, matcher, context)
    }

    fn intent_for(from: SpendCondition, amount: u64, fee: FeePolicy) -> TxIntent {
        TxIntent {
            id: IntentId::from_u128(1),
            from: vec![from],
            recipients: vec![Recipient::to_pkh(hash(500), amount)],
            refund_to: None,
            fee,
            note_selection: NoteSelection::Auto,
            deadline: None,
        }
    }

    #[test]
    fn plans_a_simple_payment() {
        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let intent = intent_for(from, 100_000, FeePolicy::Auto);

        let plan =
            plan(&intent, &classified, &matcher, &context, &chain_context()).expect("plans");

        assert_eq!(plan.input_count(), 1);
        assert!(plan.fee() >= 100, "fee must respect the minimum floor");
        // Recipient output plus refund.
        assert_eq!(plan.assembled.outputs.len(), 2);
        assert!(plan
            .assembled
            .outputs
            .iter()
            .any(|o| o.amount == 100_000));
    }

    #[test]
    fn recipient_lock_root_matches_the_first_name_the_recipient_will_see() {
        // A mismatch here fails in the worst possible way: the recipient's
        // wallet queries a first-name derived from their
        // own lock, and if the driver paid a different lock root the money is
        // invisible rather than missing.
        let recipient_lock = SpendCondition::simple_pkh(hash(500));
        let root = lock_root(&recipient_lock).expect("hashes");
        let expected = FirstName::from_lock_root(&root).expect("derives");
        assert_eq!(
            recipient_lock.first_name().expect("derives"),
            expected,
            "lock_root must feed FirstName::from_lock_root to the same digest \
             SpendCondition::first_name produces"
        );

        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let intent = intent_for(from, 100_000, FeePolicy::Auto);
        let plan =
            plan(&intent, &classified, &matcher, &context, &chain_context()).expect("plans");
        assert!(
            plan.assembled
                .outputs
                .iter()
                .any(|o| o.lock_root == root),
            "the recipient output must carry the recipient's own lock root"
        );
    }

    #[test]
    fn insufficient_funds_reports_the_reachable_balance() {
        let (from, classified, matcher, context) = wallet(&[1_000]);
        let intent = intent_for(from, 10_000_000, FeePolicy::Auto);

        let err = plan(&intent, &classified, &matcher, &context, &chain_context())
            .expect_err("cannot afford this");

        match err {
            RejectReason::InsufficientFunds { available, .. } => {
                assert_eq!(available, 1_000);
            }
            other => panic!("expected InsufficientFunds, got {other:?}"),
        }
    }

    #[test]
    fn exact_fee_below_the_minimum_is_rejected() {
        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let intent = intent_for(from, 100_000, FeePolicy::Exact(1));

        let err = plan(&intent, &classified, &matcher, &context, &chain_context())
            .expect_err("fee is below the floor");

        assert!(matches!(err, RejectReason::PlanRejected { .. }));
    }

    #[test]
    fn at_least_raises_the_fee_and_the_refund_absorbs_it() {
        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let auto = plan(
            &intent_for(from.clone(), 100_000, FeePolicy::Auto),
            &classified,
            &matcher,
            &context,
            &chain_context(),
        )
        .expect("plans");

        let raised_floor = auto.fee() + 50_000;
        let raised = plan(
            &intent_for(from, 100_000, FeePolicy::AtLeast(raised_floor)),
            &classified,
            &matcher,
            &context,
            &chain_context(),
        )
        .expect("plans");

        assert!(raised.fee() >= raised_floor);
        // The extra fee must come out of the refund, never out of the
        // recipient's output.
        assert!(raised
            .assembled
            .outputs
            .iter()
            .any(|o| o.amount == 100_000));
        assert!(raised.total_spent() <= 1_000_000);
    }

    #[test]
    fn every_input_carries_its_unlocking_spend_condition() {
        let (from, classified, matcher, context) = wallet(&[400_000, 400_000, 400_000]);
        let intent = intent_for(from.clone(), 900_000, FeePolicy::Auto);

        let plan =
            plan(&intent, &classified, &matcher, &context, &chain_context()).expect("plans");

        assert!(plan.input_count() >= 3);
        assert!(plan.assembled.inputs.iter().all(|i| i.lock == from));
        // Deduplicated: three inputs sharing one lock yield one condition.
        assert_eq!(plan.spend_conditions, vec![from]);
    }

    #[test]
    fn zero_value_refund_output_is_not_emitted() {
        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let intent = intent_for(from, 100_000, FeePolicy::Auto);
        let plan =
            plan(&intent, &classified, &matcher, &context, &chain_context()).expect("plans");
        assert!(plan.assembled.outputs.iter().all(|o| o.amount > 0));
    }

    #[test]
    fn manual_selection_of_an_absent_note_is_rejected() {
        let (from, classified, matcher, context) = wallet(&[1_000_000]);
        let mut intent = intent_for(from, 100_000, FeePolicy::Auto);
        intent.note_selection = NoteSelection::Manual(vec![Name::new(hash(9000), hash(9001))]);

        let err = plan(&intent, &classified, &matcher, &context, &chain_context())
            .expect_err("that note does not exist");

        assert!(matches!(err, RejectReason::PlanRejected { .. }));
    }
}
