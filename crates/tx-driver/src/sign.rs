//! The signing boundary.
//!
//! The driver never holds a private key. It hands a [`SignRequest`] to a
//! [`Signer`] and gets a signed `v1::RawTx` back. That is the whole contract,
//! and it is deliberately the same shape as the iris wallet provider's
//! `signRawTx({rawTx, notes, spendConditions})`: a signer is given enough
//! material to *independently verify* what it is being asked to approve, rather
//! than a summary it has to trust.
//!
//! This replaces the reconstructed driver's design, where the private key
//! travelled in-band inside the `[%tx %send ...]` effect noun and therefore
//! ended up in kernel state, in unencrypted on-disk checkpoints, and in any log
//! that dumped an effect.
//!
//! # Trusting the signer's output
//!
//! A signer is a separate authority, so its output is checked before anything
//! is submitted. [`validate_signed`] recomputes the transaction id and asserts
//! that the returned transaction spends the inputs the driver planned, pays the
//! outputs it planned, and charges the fee it planned. A signer that returns
//! anything else produces a [`RejectReason::SignerMismatch`] — terminal on
//! purpose, because a signer that substitutes a transaction once will do it
//! again, and retrying just gives it another chance.

use std::collections::BTreeMap;

use async_trait::async_trait;
use nockchain_types::tx_engine::common::{Hash, Name, TxId};
use nockchain_types::tx_engine::v1;
use nockchain_types::tx_engine::v1::tx::{Spend, SpendCondition};
use wallet_tx_builder::types::CandidateNote;

use crate::build::TxPlan;
use crate::error::RejectReason;
use crate::intent::IntentId;

/// What a signer is asked to approve and sign.
#[derive(Debug, Clone)]
pub struct SignRequest {
    /// Correlation id, so a signer that queues or prompts can attribute the
    /// request.
    pub intent_id: IntentId,
    /// The planned inputs, outputs, and fee. Authoritative.
    pub plan: TxPlan,
    /// The full notes being spent. Sidecar data: a signer may use these to
    /// render a prompt, but must verify anything it relies on against `plan`
    /// and its own view of the chain. (The iris SDK makes the same caveat about
    /// `SignTxRequest.notes`.)
    pub notes: Vec<CandidateNote>,
    /// The spend conditions unlocking those notes, deduplicated.
    pub spend_conditions: Vec<SpendCondition>,
}

impl SignRequest {
    pub fn new(intent_id: IntentId, plan: TxPlan, notes: Vec<CandidateNote>) -> Self {
        let spend_conditions = plan.spend_conditions.clone();
        Self {
            intent_id,
            plan,
            notes,
            spend_conditions,
        }
    }

    /// Total value paid out, excluding fee.
    pub fn output_total(&self) -> u64 {
        self.plan
            .assembled
            .outputs
            .iter()
            .map(|o| o.amount)
            .fold(0u64, |acc, v| acc.saturating_add(v))
    }
}

/// Why a signer refused or failed.
#[derive(Debug, thiserror::Error)]
pub enum SignError {
    /// The signer, or the human behind it, said no. Terminal.
    #[error("signer declined: {0}")]
    Declined(String),
    /// The signer could not be reached or broke down. Non-terminal: the same
    /// request may succeed later, and crucially nothing has been submitted.
    #[error("signer unavailable: {0}")]
    Unavailable(String),
    /// The signer does not hold a key the request needs. Terminal.
    #[error("signer holds no key for {0}")]
    NoSuchKey(String),
    /// The signer produced something, but not a decodable transaction.
    #[error("signer returned an undecodable transaction: {0}")]
    Undecodable(String),
}

impl SignError {
    /// Whether retrying could ever succeed.
    pub fn is_terminal(&self) -> bool {
        !matches!(self, Self::Unavailable(_))
    }
}

/// An authority that can turn a plan into a signed transaction.
#[async_trait]
pub trait Signer: Send + Sync {
    /// The public-key hashes this signer can produce signatures for.
    ///
    /// Used to build the driver's [`crate::notes::UnlockContext`], so that a
    /// note requiring a key the signer does not hold is reported as a threshold
    /// shortfall during planning instead of failing at signing time.
    async fn signer_pkhs(&self) -> std::result::Result<Vec<Hash>, SignError>;

    /// Signs the planned transaction.
    async fn sign(&self, request: SignRequest) -> std::result::Result<v1::RawTx, SignError>;
}

/// Checks that a signed transaction is the one the driver asked for.
///
/// Verifies, in order:
///
/// 1. The transaction is v1.
/// 2. Its embedded id matches the id recomputed from its own contents, so the
///    id the driver journals and polls on is the id the network will use.
/// 3. It spends exactly the planned input notes — no more, no fewer.
/// 4. It pays exactly the planned outputs, by lock root and amount.
/// 5. It charges exactly the planned fee.
/// 6. Every signature it carries actually verifies against the spend it is
///    attached to.
///
/// Steps 3–5 are what stop a compromised or buggy signer from redirecting funds
/// while returning something that superficially looks like a signed version of
/// the request. Step 6 catches corruption and forgery on the way back from the
/// signer.
///
/// # What this deliberately does not check
///
/// It does **not** prove the transaction is spendable. A `%pkh` primitive needs
/// `m` signatures and this checks only that the signatures *present* are valid,
/// not that enough of them are there; nor does it check timelocks, hash
/// preimages, or merkle proofs. Those are consensus questions, and the
/// authoritative answer is `+validate-with-context:spends` in
/// `hoon/common/tx-engine-1.hoon`, which the node runs and which returns a
/// typed reason. Reimplementing it here would create a second, divergent
/// validator — the thing this crate avoids elsewhere by reusing
/// `wallet-tx-builder`.
///
/// The division of labour: this function polices the *signer*, the network
/// polices *validity*.
pub fn validate_signed(
    plan: &TxPlan,
    signed: &v1::RawTx,
) -> std::result::Result<TxId, RejectReason> {
    if signed.version != v1::Version::V1 {
        return Err(RejectReason::SignerMismatch(format!(
            "expected a v1 transaction, got {:?}",
            signed.version
        )));
    }

    let computed = signed.compute_id().map_err(|err| {
        RejectReason::SignerMismatch(format!(
            "signed transaction id could not be computed: {err}"
        ))
    })?;
    if computed != signed.id {
        return Err(RejectReason::SignerMismatch(format!(
            "transaction carries id {} but hashes to {}",
            signed.id.to_base58(),
            computed.to_base58()
        )));
    }

    check_inputs(plan, signed)?;
    check_outputs_and_fee(plan, signed)?;
    check_signatures(signed)?;

    Ok(computed)
}

/// Verifies every signature the transaction carries.
///
/// Uses `Spend1::verify_pkh_signature`, which mirrors the Hoon
/// `+verify:affine:schnorr` including its scalar-range guards and
/// non-canonical-limb rejection, so a signature this accepts is one the network
/// will accept too.
///
/// Only `%1` (witness) spends are checked. A `%0` legacy spend carries a
/// `Signature` rather than a `PkhSignature` and has no equivalent standalone
/// verifier here; the driver plans `V1Only` candidates, so a legacy spend
/// coming back from a signer is itself the anomaly and is reported as one.
fn check_signatures(signed: &v1::RawTx) -> std::result::Result<(), RejectReason> {
    for (name, spend) in &signed.spends.0 {
        let spend1 = match spend {
            Spend::Witness(spend1) => spend1,
            Spend::Legacy(_) => {
                return Err(RejectReason::SignerMismatch(format!(
                    "signed transaction spends note {} with a legacy %0 spend, but the driver \
                     plans v1 inputs only",
                    name.first.to_base58()
                )))
            }
        };

        for entry in &spend1.witness.pkh_signature.0 {
            spend1.verify_pkh_signature(entry).map_err(|err| {
                RejectReason::SignerMismatch(format!(
                    "signature for note {} did not verify: {err}",
                    name.first.to_base58()
                ))
            })?;
        }
    }
    Ok(())
}

fn check_inputs(plan: &TxPlan, signed: &v1::RawTx) -> std::result::Result<(), RejectReason> {
    let planned: Vec<[u64; 10]> = plan
        .assembled
        .inputs
        .iter()
        .map(|input| name_key(&input.note.name))
        .collect();
    let actual: Vec<[u64; 10]> = signed
        .spends
        .0
        .iter()
        .map(|(name, _)| name_key(name))
        .collect();

    let planned_set: std::collections::BTreeSet<_> = planned.iter().collect();
    let actual_set: std::collections::BTreeSet<_> = actual.iter().collect();

    if planned_set != actual_set {
        return Err(RejectReason::SignerMismatch(format!(
            "signed transaction spends {} input(s) but {} were planned, and the sets differ",
            actual.len(),
            planned.len()
        )));
    }
    if actual.len() != actual_set.len() {
        return Err(RejectReason::SignerMismatch(
            "signed transaction spends the same note more than once".into(),
        ));
    }
    Ok(())
}

fn check_outputs_and_fee(
    plan: &TxPlan,
    signed: &v1::RawTx,
) -> std::result::Result<(), RejectReason> {
    // Outputs (seeds) and fees are per-spend on the wire but per-transaction in
    // the plan, so both are aggregated before comparison. A signer is free to
    // distribute the fee across spends differently than the planner would; what
    // it is not free to do is change the total.
    let mut actual_outputs: BTreeMap<[u64; 5], u64> = BTreeMap::new();
    let mut actual_fee: u64 = 0;

    for (_, spend) in &signed.spends.0 {
        let (seeds, fee) = match spend {
            Spend::Legacy(spend0) => (&spend0.seeds, &spend0.fee),
            Spend::Witness(spend1) => (&spend1.seeds, &spend1.fee),
        };
        actual_fee = actual_fee.checked_add(fee.0 as u64).ok_or_else(|| {
            RejectReason::SignerMismatch("signed transaction fees overflow u64".into())
        })?;
        for seed in &seeds.0 {
            let entry = actual_outputs.entry(seed.lock_root.to_array()).or_insert(0);
            *entry = entry.checked_add(seed.gift.0 as u64).ok_or_else(|| {
                RejectReason::SignerMismatch("signed transaction outputs overflow u64".into())
            })?;
        }
    }

    let mut planned_outputs: BTreeMap<[u64; 5], u64> = BTreeMap::new();
    for output in &plan.assembled.outputs {
        let entry = planned_outputs
            .entry(output.lock_root.to_array())
            .or_insert(0);
        *entry = entry
            .checked_add(output.amount)
            .ok_or_else(|| RejectReason::SignerMismatch("planned outputs overflow u64".into()))?;
    }

    if actual_outputs != planned_outputs {
        return Err(RejectReason::SignerMismatch(format!(
            "signed transaction pays {} distinct lock root(s) totalling {} nicks, but the plan \
             pays {} lock root(s) totalling {} nicks",
            actual_outputs.len(),
            actual_outputs.values().sum::<u64>(),
            planned_outputs.len(),
            planned_outputs.values().sum::<u64>(),
        )));
    }

    if actual_fee != plan.assembled.fee {
        return Err(RejectReason::SignerMismatch(format!(
            "signed transaction charges a fee of {actual_fee} nicks, but {} was planned",
            plan.assembled.fee
        )));
    }

    Ok(())
}

fn name_key(name: &Name) -> [u64; 10] {
    let first = name.first.to_array();
    let last = name.last.to_array();
    [
        first[0], first[1], first[2], first[3], first[4], last[0], last[1], last[2], last[3],
        last[4],
    ]
}

/// A signer that lives somewhere else — a browser extension, a hardware wallet,
/// a signing service.
///
/// The transport is supplied by the caller as a closure, so this crate takes no
/// opinion on whether the signer is reached over a channel, gRPC, or
/// `postMessage`. What it does own is the part that must not be reimplemented
/// per transport: turning a transport failure into the right terminal /
/// non-terminal classification.
pub struct RemoteSigner<F, G> {
    pkhs: Vec<Hash>,
    sign: F,
    // `fn() -> G` rather than `G`: the marker must not make the signer's
    // `Send`/`Sync` depend on the transport's future type, which is only ever
    // created and awaited inside `sign`.
    _marker: std::marker::PhantomData<fn() -> G>,
}

impl<F, G> RemoteSigner<F, G>
where
    F: Fn(SignRequest) -> G + Send + Sync,
    G: std::future::Future<Output = std::result::Result<v1::RawTx, SignError>> + Send,
{
    /// Builds a remote signer from the key hashes it advertises and a transport.
    ///
    /// The advertised hashes are used only for planning; a signer that lies
    /// about them causes planning to select notes it cannot sign, which fails
    /// closed at signing time rather than producing a bad transaction.
    pub fn new(pkhs: Vec<Hash>, sign: F) -> Self {
        Self {
            pkhs,
            sign,
            _marker: std::marker::PhantomData,
        }
    }
}

#[async_trait]
impl<F, G> Signer for RemoteSigner<F, G>
where
    F: Fn(SignRequest) -> G + Send + Sync,
    G: std::future::Future<Output = std::result::Result<v1::RawTx, SignError>> + Send,
{
    async fn signer_pkhs(&self) -> std::result::Result<Vec<Hash>, SignError> {
        Ok(self.pkhs.clone())
    }

    async fn sign(&self, request: SignRequest) -> std::result::Result<v1::RawTx, SignError> {
        (self.sign)(request).await
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use nockchain_math::belt::Belt;
    use nockchain_types::tx_engine::common::{BlockHeight, Nicks, Version};
    use nockchain_types::tx_engine::v1::note::NoteData;
    use nockchain_types::tx_engine::v1::tx::{Seed, Seeds, Spend1, Witness};
    use wallet_tx_builder::types::{
        AssembledInput, AssembledOutput, AssembledTransaction, CandidateIdentity,
    };

    use super::*;

    pub(crate) fn hash(seed: u64) -> Hash {
        Hash([Belt(seed + 1), Belt(seed + 2), Belt(seed + 3), Belt(seed + 4), Belt(seed + 5)])
    }

    fn name(seed: u64) -> Name {
        Name::new(hash(seed), hash(seed + 1000))
    }

    /// A plan spending one note, paying `outputs`, charging `fee`.
    pub(crate) fn plan_with(outputs: Vec<(Hash, u64)>, fee: u64) -> TxPlan {
        TxPlan {
            assembled: AssembledTransaction {
                inputs: vec![AssembledInput {
                    note: CandidateIdentity {
                        name: name(1),
                        origin_page: BlockHeight(Belt(1)),
                    },
                    lock: SpendCondition::simple_pkh(hash(1)),
                }],
                outputs: outputs
                    .into_iter()
                    .map(|(lock_root, amount)| AssembledOutput { lock_root, amount })
                    .collect(),
                fee,
            },
            spend_conditions: vec![SpendCondition::simple_pkh(hash(1))],
            debug_trace: vec![],
        }
    }

    fn seed(lock_root: Hash, gift: u64) -> Seed {
        Seed {
            output_source: None,
            lock_root,
            note_data: NoteData(vec![]),
            gift: Nicks(gift as usize),
            parent_hash: hash(77),
        }
    }

    fn witness() -> Witness {
        Witness {
            lock_merkle_proof: nockchain_types::tx_engine::v1::tx::LockMerkleProof::new_stub(
                SpendCondition::simple_pkh(hash(1)),
                1,
                nockchain_types::tx_engine::v1::tx::MerkleProof {
                    root: hash(2),
                    path: vec![],
                },
            ),
            pkh_signature: nockchain_types::tx_engine::v1::tx::PkhSignature(vec![]),
            hax: vec![],
            tim: 0,
        }
    }

    /// A signed transaction spending `input_name`, paying `seeds`, charging `fee`.
    pub(crate) fn signed_with(input_name: Name, seeds: Vec<(Hash, u64)>, fee: u64) -> v1::RawTx {
        let spend = Spend::Witness(Spend1 {
            witness: witness(),
            seeds: Seeds(
                seeds
                    .into_iter()
                    .map(|(lock_root, gift)| seed(lock_root, gift))
                    .collect(),
            ),
            fee: Nicks(fee as usize),
        });
        let mut tx = v1::RawTx {
            version: Version::V1,
            id: hash(0),
            spends: v1::Spends(vec![(input_name, spend)]),
        };
        tx.id = tx.compute_id().expect("id computes");
        tx
    }

    #[test]
    fn a_faithful_signature_validates() {
        let plan = plan_with(vec![(hash(50), 900), (hash(1), 50)], 50);
        let signed = signed_with(name(1), vec![(hash(50), 900), (hash(1), 50)], 50);
        let tx_id = validate_signed(&plan, &signed).expect("validates");
        assert_eq!(tx_id, signed.id);
    }

    #[test]
    fn a_tampered_transaction_id_is_rejected() {
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let mut signed = signed_with(name(1), vec![(hash(50), 900)], 50);
        signed.id = hash(12345);
        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn a_redirected_output_is_rejected() {
        // The attack this check exists for: the signer keeps the amounts and
        // the fee, but sends the money somewhere else.
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(1), vec![(hash(999), 900)], 50);
        let err = validate_signed(&plan, &signed).expect_err("redirected funds");
        assert!(matches!(err, RejectReason::SignerMismatch(_)));
    }

    #[test]
    fn an_extra_output_is_rejected() {
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(1), vec![(hash(50), 900), (hash(999), 10)], 50);
        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn a_reduced_output_is_rejected() {
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(1), vec![(hash(50), 800)], 50);
        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn an_inflated_fee_is_rejected() {
        // A signer skimming the difference into the fee, which a miner it
        // controls then collects.
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(1), vec![(hash(50), 900)], 5_000);
        let err = validate_signed(&plan, &signed).expect_err("inflated fee");
        assert!(matches!(err, RejectReason::SignerMismatch(_)));
    }

    #[test]
    fn a_substituted_input_is_rejected() {
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(42), vec![(hash(50), 900)], 50);
        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn a_v0_transaction_is_rejected() {
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let mut signed = signed_with(name(1), vec![(hash(50), 900)], 50);
        signed.version = Version::V0;
        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn splitting_one_output_across_seeds_still_validates() {
        // Aggregation is intentional: how a signer arranges seeds within the
        // transaction is its business, as long as the totals per lock root and
        // the overall fee match the plan.
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let signed = signed_with(name(1), vec![(hash(50), 400), (hash(50), 500)], 50);
        validate_signed(&plan, &signed).expect("split seeds are equivalent");
    }

    #[test]
    fn a_signature_whose_pubkey_does_not_match_its_pkh_is_rejected() {
        // The cheap forgery: claim a signature is from key X while carrying a
        // pubkey for key Y. Caught before any curve arithmetic.
        use nockchain_types::tx_engine::common::{SchnorrPubkey, SchnorrSignature};
        use nockchain_types::tx_engine::v1::tx::PkhSignatureEntry;

        let plan = plan_with(vec![(hash(50), 900)], 50);
        let mut signed = signed_with(name(1), vec![(hash(50), 900)], 50);

        let entry = PkhSignatureEntry {
            pkh: hash(4242),
            pubkey: SchnorrPubkey(nockchain_math::crypto::cheetah::A_GEN),
            signature: SchnorrSignature {
                chal: [Belt(1); 8],
                sig: [Belt(1); 8],
            },
        };
        if let Spend::Witness(spend1) = &mut signed.spends.0[0].1 {
            spend1.witness.pkh_signature =
                nockchain_types::tx_engine::v1::tx::PkhSignature(vec![entry]);
        }
        signed.id = signed.compute_id().expect("id computes");

        let err = validate_signed(&plan, &signed).expect_err("forged signature entry");
        assert!(matches!(err, RejectReason::SignerMismatch(_)));
        assert!(
            err.to_string().contains("did not verify"),
            "the message should name the failing check: {err}"
        );
    }

    #[test]
    fn a_legacy_v0_spend_is_rejected() {
        use nockchain_types::tx_engine::common::Signature;
        use nockchain_types::tx_engine::v1::tx::Spend0;

        let plan = plan_with(vec![(hash(50), 900)], 50);
        let mut signed = signed_with(name(1), vec![(hash(50), 900)], 50);
        let seeds = match &signed.spends.0[0].1 {
            Spend::Witness(spend1) => spend1.seeds.clone(),
            Spend::Legacy(_) => unreachable!(),
        };
        signed.spends.0[0].1 = Spend::Legacy(Spend0 {
            signature: Signature(vec![]),
            seeds,
            fee: Nicks(50),
        });
        signed.id = signed.compute_id().expect("id computes");

        assert!(matches!(
            validate_signed(&plan, &signed),
            Err(RejectReason::SignerMismatch(_))
        ));
    }

    #[test]
    fn unavailable_is_the_only_retryable_sign_error() {
        assert!(!SignError::Unavailable("timeout".into()).is_terminal());
        assert!(SignError::Declined("user said no".into()).is_terminal());
        assert!(SignError::NoSuchKey("abc".into()).is_terminal());
        assert!(SignError::Undecodable("garbage".into()).is_terminal());
    }

    #[tokio::test]
    async fn a_remote_signer_round_trips_a_request() {
        let expected = signed_with(name(1), vec![(hash(50), 900)], 50);
        let returned = expected.clone();
        let signer = RemoteSigner::new(vec![hash(1)], move |_request: SignRequest| {
            let tx = returned.clone();
            async move { Ok(tx) }
        });

        assert_eq!(signer.signer_pkhs().await.unwrap(), vec![hash(1)]);
        let plan = plan_with(vec![(hash(50), 900)], 50);
        let request = SignRequest::new(IntentId::from_u128(1), plan.clone(), vec![]);
        let signed = signer.sign(request).await.expect("signs");
        validate_signed(&plan, &signed).expect("validates");
    }
}
