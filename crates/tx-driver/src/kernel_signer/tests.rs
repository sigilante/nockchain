//! Conformance tests for [`KernelSigner`], against a real Hoon wallet kernel.
//!
//! These boot the actual wallet kernel, so they are slow and they are the only
//! place in this crate where a Hoon signature is produced. That is the point: a
//! signer that is only ever exercised against a mock proves nothing about the
//! kernel it is meant to drive, and the failure mode this module exists to
//! prevent — the kernel quietly re-planning the transaction — is invisible to
//! any test that does not run the kernel.

use std::sync::Arc;
use std::time::Duration;

use nockchain_math::belt::Belt;
use nockchain_types::blockchain_constants::default_fakenet_blockchain_constants;
use nockchain_types::tx_engine::common::{BlockHeight, Hash, Name};
use nockchain_types::tx_engine::v1;
use nockchain_types::tx_engine::v1::tx::{LockPrimitive, Pkh, SpendCondition};
use wallet_tx_builder::types::ChainContext;

use super::*;
use crate::build::plan;
use crate::chain::ChainSource;
use crate::driver::{ConfirmPolicy, TxDriver, TxDriverConfig};
use crate::intent::{FeePolicy, IntentId, NoteSelection, Recipient, TxIntent, TxOutcome};
use crate::notes::{classify as classify_notes, SpendConditionMatcher, UnlockContext};
use crate::sign::validate_signed;
use crate::testing::{note_for, MockChainSource};

const HEIGHT: u64 = 1_000;

/// A `ChainContext` derived from the same constants the kernel is given.
///
/// This has to line up. The driver prices the transaction from these numbers
/// and pins the result; the kernel re-checks that fee against its *own*
/// constants and, with `allow-low-fee` false, refuses anything short. Two sets
/// of constants means a fee the kernel rejects for reasons that have nothing to
/// do with the driver being wrong.
fn chain_context() -> ChainContext {
    let constants = default_fakenet_blockchain_constants();
    ChainContext {
        height: BlockHeight(Belt(HEIGHT)),
        bythos_phase: BlockHeight(Belt(constants.bythos_phase)),
        base_fee: constants.base_fee,
        input_fee_divisor: constants.input_fee_divisor,
        min_fee: constants.note_data.min_fee,
    }
}

/// Boots a signer holding a freshly generated key.
///
/// `seed` varies the entropy so two signers in one test hold different keys —
/// which is what makes "a note this signer cannot open" expressible.
async fn signer_with_key(seed: u8) -> (Arc<KernelSigner>, Hash) {
    let signer = KernelSigner::new(KernelSignerConfig {
        data_dir: None,
        key_source: KeySource::Generate {
            entropy: [seed; 32],
            salt: [seed.wrapping_add(1); 16],
        },
        sign_keys: Vec::new(),
        chain_constants: Some(default_fakenet_blockchain_constants()),
        timeout: Duration::from_secs(300),
    })
    .await
    .expect("the wallet kernel boots and generates a key");

    let pkh = signer
        .signer_pkhs()
        .await
        .expect("signer reports its keys")
        .first()
        .cloned()
        .expect("keygen produces at least one signing key");

    (Arc::new(signer), pkh)
}

/// A driver wired to `signer` over a chain holding `notes`.
async fn driver_with(
    signer: Arc<KernelSigner>,
    notes: Vec<(Name, v1::Note)>,
    journal: &tempfile::TempDir,
) -> (Arc<TxDriver>, Arc<MockChainSource>) {
    let chain = Arc::new(MockChainSource::new(HEIGHT, notes).with_context(chain_context()));
    let driver = TxDriver::new(
        TxDriverConfig {
            journal_dir: journal.path().to_path_buf(),
            confirm: ConfirmPolicy::NoWait,
            ..TxDriverConfig::default()
        },
        Arc::clone(&chain) as Arc<dyn ChainSource>,
        signer as Arc<dyn crate::sign::Signer>,
    )
    .await
    .expect("journal opens");
    (Arc::new(driver), chain)
}

fn payment(id: u128, from: SpendCondition, to: Hash, amount: u64) -> TxIntent {
    TxIntent {
        id: IntentId::from_u128(id),
        from: vec![from],
        recipients: vec![Recipient::to_pkh(to, amount)],
        refund_to: None,
        fee: FeePolicy::Auto,
        note_selection: NoteSelection::Auto,
        deadline: None,
    }
}

/// Plans an intent the way the driver does, so a test can hand the resulting
/// plan straight to the signer without going through submission.
async fn plan_for(
    chain: &MockChainSource,
    signer: &KernelSigner,
    intent: &TxIntent,
) -> (crate::build::TxPlan, SignRequest) {
    let (matcher, _) = SpendConditionMatcher::new(intent.from.clone());
    let context = UnlockContext::new()
        .with_signer_pkhs(signer.signer_pkhs().await.expect("signer reports its keys"));
    let snapshot = chain
        .balance(&matcher.first_names())
        .await
        .expect("mock chain answers");
    let classified = classify_notes(&snapshot, &matcher, &context);
    let plan =
        plan(intent, &classified, &matcher, &context, &chain_context()).expect("the intent plans");

    let spent = snapshot
        .notes
        .iter()
        .filter(|(name, _)| {
            plan.assembled
                .inputs
                .iter()
                .any(|input| &input.note.name == name)
        })
        .cloned()
        .collect::<Vec<_>>();
    let request = SignRequest::new(
        intent.id,
        plan.clone(),
        Vec::new(),
        crate::sign::ChainState {
            height: snapshot.height.clone(),
            block_id: snapshot.block_id.clone(),
        },
        spent,
    );
    (plan, request)
}

// ---------------------------------------------------------------------------

/// §7.1 — the baseline. If this fails nothing else matters.
#[tokio::test]
async fn a_kernel_signature_validates_against_the_plan() {
    let (signer, pkh) = signer_with_key(7).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    let (name, note) = note_for(&lock, 1, 1, 1_000_000);

    let chain = MockChainSource::new(HEIGHT, vec![(name, note)]).with_context(chain_context());
    let intent = payment(1, lock, crate::testing::hash(500), 100_000);
    let (plan, request) = plan_for(&chain, &signer, &intent).await;

    let signed = signer.sign(request).await.expect("the kernel signs");
    validate_signed(&plan, &signed).expect("the kernel's transaction is the driver's transaction");
}

/// §7.2 — the failure this whole module is built to prevent. `validate_signed`
/// would catch a divergence anyway; asserting on the transaction directly is
/// what makes it clear *which* thing diverged.
#[tokio::test]
async fn the_kernel_spends_the_planned_inputs_and_charges_the_planned_fee() {
    let (signer, pkh) = signer_with_key(11).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    // Several notes, so an unconstrained kernel has room to select differently.
    let notes: Vec<_> = (0..4)
        .map(|i| note_for(&lock, 100 + i, 1, 300_000))
        .collect();

    let chain = MockChainSource::new(HEIGHT, notes).with_context(chain_context());
    let intent = payment(2, lock, crate::testing::hash(500), 700_000);
    let (plan, request) = plan_for(&chain, &signer, &intent).await;

    let signed = signer.sign(request).await.expect("the kernel signs");

    let mut planned: Vec<_> = plan
        .assembled
        .inputs
        .iter()
        .map(|input| input.note.name.first.to_base58())
        .collect();
    let mut actual: Vec<_> = signed
        .spends
        .0
        .iter()
        .map(|(name, _)| name.first.to_base58())
        .collect();
    planned.sort();
    actual.sort();
    assert_eq!(actual, planned, "the kernel selected its own inputs");

    let charged: u64 = signed
        .spends
        .0
        .iter()
        .map(|(_, spend)| match spend {
            v1::Spend::Witness(spend1) => spend1.fee.0 as u64,
            v1::Spend::Legacy(spend0) => spend0.fee.0 as u64,
        })
        .sum();
    assert_eq!(charged, plan.assembled.fee, "the kernel repriced the fee");
}

/// §7.3 — the residency test. A kernel that dies after one signature passes
/// every other test in this file.
#[tokio::test]
async fn one_signer_serves_three_signatures() {
    let (signer, pkh) = signer_with_key(13).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    let notes: Vec<_> = (0..3)
        .map(|i| note_for(&lock, 200 + i, 1, 500_000))
        .collect();

    for (round, (name, note)) in notes.into_iter().enumerate() {
        let chain = MockChainSource::new(HEIGHT, vec![(name, note)]).with_context(chain_context());
        let intent = payment(
            10 + round as u128,
            lock.clone(),
            crate::testing::hash(500),
            100_000,
        );
        let (plan, request) = plan_for(&chain, &signer, &intent).await;
        let signed = signer
            .sign(request)
            .await
            .unwrap_or_else(|err| panic!("signature {} failed: {err}", round + 1));
        validate_signed(&plan, &signed)
            .unwrap_or_else(|err| panic!("signature {} did not validate: {err}", round + 1));
    }
}

/// §7.4 — two intents in flight against one signer. The signer serialises
/// internally; what must not happen is a crossed reply or a shared transaction.
#[tokio::test]
async fn concurrent_intents_get_distinct_transactions() {
    let (signer, pkh) = signer_with_key(17).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    let notes: Vec<_> = (0..2)
        .map(|i| note_for(&lock, 300 + i, 1, 500_000))
        .collect();

    let journal = tempfile::tempdir().expect("tempdir");
    let (driver, _chain) = driver_with(signer, notes, &journal).await;

    let first = {
        let driver = Arc::clone(&driver);
        let lock = lock.clone();
        tokio::spawn(async move {
            driver
                .submit(payment(21, lock, crate::testing::hash(500), 50_000))
                .await
        })
    };
    let second = {
        let driver = Arc::clone(&driver);
        tokio::spawn(async move {
            driver
                .submit(payment(22, lock, crate::testing::hash(501), 60_000))
                .await
        })
    };

    let first = first.await.expect("task joins").expect("verdict reached");
    let second = second.await.expect("task joins").expect("verdict reached");

    let ids = [&first, &second].map(|outcome| match outcome {
        TxOutcome::Submitted { id, tx_id } => (id.as_u128(), tx_id.to_base58()),
        other => panic!("expected a submission, got {other:?}"),
    });

    assert_ne!(
        ids[0].1, ids[1].1,
        "both intents produced the same transaction"
    );
    let mut correlation: Vec<_> = ids.iter().map(|(id, _)| *id).collect();
    correlation.sort_unstable();
    assert_eq!(
        correlation,
        vec![21, 22],
        "outcomes lost their correlation ids"
    );
}

/// §7.5 — `signer_pkhs` feeds planning, so a note this kernel cannot open must
/// be filtered out *there*, with a reason, rather than blowing up at signing
/// time with an opaque kernel error.
#[tokio::test]
async fn a_note_the_kernel_cannot_open_never_reaches_the_signer() {
    let (signer, _mine) = signer_with_key(23).await;
    let (_stranger, theirs) = signer_with_key(29).await;

    let their_lock = SpendCondition::simple_pkh(theirs);
    let (name, note) = note_for(&their_lock, 400, 1, 1_000_000);

    let journal = tempfile::tempdir().expect("tempdir");
    let (driver, _chain) = driver_with(signer, vec![(name, note)], &journal).await;

    let outcome = driver
        .submit(payment(31, their_lock, crate::testing::hash(500), 100_000))
        .await
        .expect("verdict reached");

    match outcome {
        TxOutcome::Rejected { reason, .. } => {
            let message = reason.to_string();
            assert!(
                message.contains("funds") || message.contains("no inputs"),
                "a note the signer cannot open should read as unspendable balance, not as a \
                 signing failure: {message}"
            );
        }
        other => panic!("expected a rejection at planning time, got {other:?}"),
    }
}

/// §7.6 — a signer that hangs must be non-terminal. A false terminal verdict
/// strands a recoverable intent; there is nothing to roll back, because nothing
/// was submitted.
#[tokio::test]
async fn a_timed_out_kernel_reports_unavailable_and_stays_recoverable() {
    let (fast, pkh) = signer_with_key(31).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    let (name, note) = note_for(&lock, 500, 1, 1_000_000);

    // A second signer holding the same key, but given no time to answer.
    let wedged = KernelSigner::new(KernelSignerConfig {
        data_dir: None,
        key_source: KeySource::Generate {
            entropy: [31; 32],
            salt: [32; 16],
        },
        sign_keys: Vec::new(),
        chain_constants: Some(default_fakenet_blockchain_constants()),
        timeout: Duration::from_nanos(1),
    })
    .await
    .expect("boot happens before the timeout applies to signing");

    let chain = MockChainSource::new(HEIGHT, vec![(name, note)]).with_context(chain_context());
    let intent = payment(41, lock, crate::testing::hash(500), 100_000);
    let (_plan, request) = plan_for(&chain, &fast, &intent).await;

    let err = wedged
        .sign(request)
        .await
        .expect_err("a one-nanosecond budget cannot be met");
    assert!(
        !err.is_terminal(),
        "a timeout must stay retryable, but produced {err}"
    );
    assert!(
        matches!(err, SignError::Unavailable(_)),
        "expected Unavailable, got {err}"
    );
}

/// §7.7 — the kernel's native output is a file write. Nothing here may take it
/// up on that.
#[tokio::test]
async fn signing_writes_no_transaction_to_disk() {
    let workdir = tempfile::tempdir().expect("tempdir");
    let (signer, pkh) = signer_with_key(37).await;
    let lock = SpendCondition::simple_pkh(pkh.clone());
    let (name, note) = note_for(&lock, 600, 1, 1_000_000);

    let chain = MockChainSource::new(HEIGHT, vec![(name, note)]).with_context(chain_context());
    let intent = payment(51, lock, crate::testing::hash(500), 100_000);
    let (plan, request) = plan_for(&chain, &signer, &intent).await;
    let signed = signer.sign(request).await.expect("the kernel signs");
    validate_signed(&plan, &signed).expect("validates");

    // The kernel writes to `./txs/<name>.tx`, relative to the process working
    // directory, so both that and the signer's own scratch space are checked.
    let mut found = Vec::new();
    for root in [workdir.path(), std::path::Path::new("./txs")] {
        collect_tx_files(root, &mut found);
    }
    assert!(
        found.is_empty(),
        "a signed transaction reached the disk: {found:?}"
    );
}

fn collect_tx_files(root: &std::path::Path, out: &mut Vec<std::path::PathBuf>) {
    let Ok(entries) = std::fs::read_dir(root) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            collect_tx_files(&path, out);
        } else if path.extension().and_then(|ext| ext.to_str()) == Some("tx") {
            out.push(path);
        }
    }
}

/// §7.8 — a multisig note's note-data omits its lock, so the kernel has to be
/// handed the participants to rebuild it. Without the `multisig` field this
/// input is simply unspendable.
#[tokio::test]
async fn a_multisig_input_signs_with_the_participants_supplied() {
    let (signer, mine) = signer_with_key(41).await;
    let (_other, theirs) = signer_with_key(43).await;

    // 1-of-2: this signer alone can satisfy it, but the lock is still m-of-n
    // and so still needs reconstructing.
    let lock = SpendCondition::new(vec![LockPrimitive::Pkh(Pkh::new(
        1,
        vec![mine.clone(), theirs],
    ))]);
    let (name, note) = note_for(&lock, 700, 1, 1_000_000);

    let chain = MockChainSource::new(HEIGHT, vec![(name, note)]).with_context(chain_context());
    let intent = payment(61, lock, crate::testing::hash(500), 100_000);
    let (plan, request) = plan_for(&chain, &signer, &intent).await;

    let signed = signer
        .sign(request)
        .await
        .expect("the kernel rebuilds the multisig input lock and signs");
    validate_signed(&plan, &signed).expect("validates");
}

// ---------------------------------------------------------------------------
// Encoding tests. These need no kernel.
// ---------------------------------------------------------------------------

#[test]
fn a_simple_lock_asks_for_no_multisig_reconstruction() {
    let mut slab: NounSlab = NounSlab::new();
    let plan = crate::sign::tests::plan_with(vec![(crate::testing::hash(50), 900)], 50);
    let request = SignRequest::new(
        IntentId::from_u128(1),
        plan,
        Vec::new(),
        crate::sign::tests::chain_state(),
        Vec::new(),
    );
    let noun = multisig_noun(&mut slab, &request).expect("encodes");
    assert!(
        unsafe { noun.raw_equals(&D(0)) },
        "a 1-of-1 pkh lock is one the kernel can already derive; sending a reconstruction \
         payload would make it rebuild a lock it did not need"
    );
}

#[test]
fn two_distinct_multisig_locks_are_refused_rather_than_silently_truncated() {
    // The cause has room for exactly one reconstructed input lock. Picking one
    // and dropping the other would produce a transaction that fails to unlock
    // half its inputs, which is far worse than declining.
    let mut slab: NounSlab = NounSlab::new();
    let mut plan = crate::sign::tests::plan_with(vec![(crate::testing::hash(50), 900)], 50);
    plan.spend_conditions = vec![
        SpendCondition::new(vec![LockPrimitive::Pkh(Pkh::new(
            2,
            vec![crate::testing::hash(1), crate::testing::hash(2)],
        ))]),
        SpendCondition::new(vec![LockPrimitive::Pkh(Pkh::new(
            2,
            vec![crate::testing::hash(3), crate::testing::hash(4)],
        ))]),
    ];
    let request = SignRequest::new(
        IntentId::from_u128(1),
        plan,
        Vec::new(),
        crate::sign::tests::chain_state(),
        Vec::new(),
    );

    let err = multisig_noun(&mut slab, &request).expect_err("two locks cannot both be sent");
    assert!(matches!(err, SignError::Declined(_)));
}

#[test]
fn a_kernel_that_reselected_inputs_is_named_as_a_parity_failure() {
    // The diagnosis matters: `validate_signed` would report this as a generic
    // `SignerMismatch` two layers up, which reads like a broken signature
    // rather than a kernel that ignored the `names` list.
    let plan = crate::sign::tests::plan_with(vec![(crate::testing::hash(50), 900)], 50);
    let request = SignRequest::new(
        IntentId::from_u128(1),
        plan,
        Vec::new(),
        crate::sign::tests::chain_state(),
        Vec::new(),
    );
    let substituted = crate::sign::tests::signed_with(
        Name::new(crate::testing::hash(999), crate::testing::hash(998)),
        vec![(crate::testing::hash(50), 900)],
        50,
    );

    let err = ensure_input_parity(&request, &substituted).expect_err("inputs differ");
    assert!(
        err.to_string().contains("parity"),
        "the message should name the actual problem: {err}"
    );
    assert!(err.is_terminal(), "a re-planning kernel will re-plan again");
}

#[test]
fn a_kernel_reply_bearing_key_material_is_never_forwarded() {
    // `kernel_explanation` feeds a `SignError`, which the driver journals to
    // disk and pokes back to the kernel. The wallet's `%markdown` channel is
    // also how it prints seed phrases, so the two must never meet. This is the
    // shape of a real `keygen` reply.
    let mut slab: NounSlab = NounSlab::new();
    let tag = make_tas(&mut slab, "markdown").as_noun();
    let body = make_tas(
        &mut slab,
        "## Generated New Master Key\n### Seed Phrase (save this for import)\n\
         'only ten inspire accuse upgrade wheat witness wood amount oppose amateur maximum'\n\
         ### Extended Private Key (save this for import)\nzprvLxxkCBq3s5HYzkem5RVqpGdAz",
    )
    .as_noun();
    let noun = T(&mut slab, &[tag, body]);
    slab.set_root(noun);

    let explanation = kernel_explanation(std::slice::from_ref(&slab));
    for leak in ["only ten inspire", "zprv", "Seed Phrase"] {
        assert!(
            !explanation.contains(leak),
            "key material reached an error string via {leak:?}: {explanation}"
        );
    }
    assert!(
        explanation.contains("redacted"),
        "the drop should be visible: {explanation}"
    );
}

#[test]
fn an_ordinary_kernel_complaint_is_still_forwarded_verbatim() {
    // Redaction must not swallow the diagnostic that makes a stale kernel
    // recognisable, or the filter above just trades one silent failure for
    // another.
    let mut slab: NounSlab = NounSlab::new();
    let tag = make_tas(&mut slab, "markdown").as_noun();
    let body = make_tas(&mut slab, "## Poke failed").as_noun();
    let noun = T(&mut slab, &[tag, body]);
    slab.set_root(noun);

    assert_eq!(
        kernel_explanation(std::slice::from_ref(&slab)),
        "## Poke failed"
    );
}
