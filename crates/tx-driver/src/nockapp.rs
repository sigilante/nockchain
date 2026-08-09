//! The NockApp `IODriverFn` adapter.
//!
//! A thin shell over [`TxDriver`]: it decodes `[%tx %send ...]` effects, runs
//! them through the library, and pokes a correlated cause back into the kernel.
//! All policy lives in the library, so a non-NockApp host (a service, a test, a
//! CLI) gets identical behaviour without pulling in this module.
//!
//! # Wire protocol
//!
//! ```hoon
//! ::  effect in
//! +$  effect
//!   $%  $:  %tx
//!           %send
//!           id=@ux                  :: correlation id, echoed on the cause
//!           src-lock=spend-condition
//!           trg-lock=spend-condition
//!           amount=@                :: nicks
//!       ==
//!       ...
//!   ==
//!
//! ::  cause out — `id` is present on every variant
//! +$  cause
//!   $%  [%tx-confirmed id=@ux tx-id=@t height=@]
//!       [%tx-submitted id=@ux tx-id=@t]
//!       [%tx-rejected id=@ux reason=@t]   :: terminal; safe to roll back
//!       [%tx-failed id=@ux error=@t]      :: non-terminal; status unknown
//!   ==
//! ```
//!
//! Two differences from the protocol this replaces, both deliberate:
//!
//! - **`id` is threaded end to end.** The old effect carried no request
//!   identifier and the old cause was `[%tx-sent tx-hash=@t]`, so a kernel with
//!   two payouts in flight could not tell which result belonged to which
//!   request. A known consumer tried to work around this by adding its own
//!   request id to its cause type while the field stayed commented out of the
//!   emitted effect, so the decode failed and the kernel crashed on a
//!   *successful* payout.
//! - **`src-privkey` is gone.** The kernel names the spending lock; the key
//!   lives in the driver's [`crate::sign::Signer`] and never enters kernel
//!   state or an on-disk checkpoint (§6.2).
//!
//! `%tx-rejected` and `%tx-failed` are distinct causes rather than one
//! `%tx-fail`, because only the first is safe to roll back against (§6.5).

use std::sync::Arc;

use nockapp::driver::{make_driver, IODriverFn, NockAppHandle};
use nockapp::noun::slab::NounSlab;
use nockapp::wire::WireRepr;
use nockchain_types::tx_engine::v1::tx::SpendCondition;
use nockvm::ext::AtomExt as CoreAtomExt;
use nockvm::noun::{Atom, Noun, NounAllocator, NounSpace, D, T};
use nockvm_macros::tas;
use noun_serde::{NounDecode, NounDecodeError, NounEncode};
use tracing::{debug, info, warn};

use crate::driver::TxDriver;
use crate::intent::{FeePolicy, IntentId, NoteSelection, Recipient, TxIntent, TxOutcome};

/// The wire source tag for pokes this driver emits.
pub const WIRE_SOURCE: &str = "tx-driver";
/// The wire version for pokes this driver emits.
pub const WIRE_VERSION: u64 = 1;

/// A decoded `%tx` effect.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TxEffect {
    /// `[%tx %send id src-lock trg-lock amount]`
    Send {
        id: IntentId,
        src_lock: SpendCondition,
        trg_lock: SpendCondition,
        amount_nicks: u64,
    },
}

impl TxEffect {
    /// The intent this effect requests.
    pub fn into_intent(self) -> TxIntent {
        match self {
            Self::Send {
                id,
                src_lock,
                trg_lock,
                amount_nicks,
            } => TxIntent {
                id,
                from: vec![src_lock],
                recipients: vec![Recipient::to_condition(trg_lock, amount_nicks)],
                refund_to: None,
                fee: FeePolicy::Auto,
                note_selection: NoteSelection::Auto,
                deadline: None,
            },
        }
    }
}

impl NounDecode for TxEffect {
    fn from_noun(effect: &Noun, space: &NounSpace) -> Result<Self, NounDecodeError> {
        let cell = effect.in_space(space).as_cell()?;
        if !cell.head().eq_bytes(b"tx") {
            return Err(NounDecodeError::InvalidTag);
        }

        let body = cell.tail().as_cell()?;
        let op = body
            .head()
            .as_atom()?
            .atom()
            .as_direct()
            .map_err(|_| NounDecodeError::InvalidTag)?
            .data();

        match op {
            t if t == tas!(b"send") => {
                // [id src-lock trg-lock amount]
                let rest = body.tail().as_cell()?;
                let id = intent_id_from_noun(&rest.head().noun(), space)?;

                let rest = rest.tail().as_cell()?;
                let src_lock = SpendCondition::from_noun(&rest.head().noun(), space)?;

                let rest = rest.tail().as_cell()?;
                let trg_lock = SpendCondition::from_noun(&rest.head().noun(), space)?;

                let amount_nicks = u64::from_noun(&rest.tail().noun(), space)?;

                Ok(Self::Send {
                    id,
                    src_lock,
                    trg_lock,
                    amount_nicks,
                })
            }
            // An unrecognised `%tx` operation is not an error for this driver:
            // the family is extensible and another driver may own the verb.
            _ => Err(NounDecodeError::InvalidTag),
        }
    }
}

/// Encodes an outcome as the cause noun to poke back into the kernel.
///
/// Every variant leads with the correlation id, so a kernel can dispatch on the
/// id before it looks at the payload.
pub fn encode_cause(outcome: &TxOutcome) -> NounSlab {
    let mut slab: NounSlab = NounSlab::new();
    let noun = {
        let id = outcome.id();
        match outcome {
            TxOutcome::Confirmed { tx_id, height, .. } => {
                let tag = tas_noun(&mut slab, "tx-confirmed");
                let id = intent_id_noun(&mut slab, id);
                let tx = string_noun(&mut slab, &tx_id.to_base58());
                let height = height.0 .0.to_noun(&mut slab);
                T(&mut slab, &[tag, id, tx, height])
            }
            TxOutcome::Submitted { tx_id, .. } => {
                let tag = tas_noun(&mut slab, "tx-submitted");
                let id = intent_id_noun(&mut slab, id);
                let tx = string_noun(&mut slab, &tx_id.to_base58());
                T(&mut slab, &[tag, id, tx])
            }
            TxOutcome::SignedNotSubmitted { tx_id, .. } => {
                // Dry run. Reported as its own cause rather than as a
                // submission, so a kernel is never told a transaction is live
                // when it is not.
                let tag = tas_noun(&mut slab, "tx-signed");
                let id = intent_id_noun(&mut slab, id);
                let tx = string_noun(&mut slab, &tx_id.to_base58());
                T(&mut slab, &[tag, id, tx])
            }
            TxOutcome::Rejected { reason, .. } => {
                let tag = tas_noun(&mut slab, "tx-rejected");
                let id = intent_id_noun(&mut slab, id);
                let reason = string_noun(&mut slab, &reason.to_string());
                T(&mut slab, &[tag, id, reason])
            }
            TxOutcome::Failed { error, .. } => {
                let tag = tas_noun(&mut slab, "tx-failed");
                let id = intent_id_noun(&mut slab, id);
                let error = string_noun(&mut slab, &error.to_string());
                T(&mut slab, &[tag, id, error])
            }
        }
    };
    slab.set_root(noun);
    slab
}

/// Encodes a correlation id as a single atom, the Hoon `@ux` a kernel expects.
///
/// Atoms are little-endian, so the id's numeric value is written LE here even
/// though [`IntentId`] stores its bytes big-endian.
fn intent_id_noun<A: NounAllocator>(allocator: &mut A, id: IntentId) -> Noun {
    Atom::from_bytes(allocator, &id.as_u128().to_le_bytes()).as_noun()
}

/// Decodes a correlation id from an atom.
///
/// Hoon strips leading zero bytes from atoms, so a short atom is
/// zero-extended rather than rejected. An atom wider than 16 bytes is not a
/// valid id and is refused instead of being silently truncated.
fn intent_id_from_noun(noun: &Noun, space: &NounSpace) -> Result<IntentId, NounDecodeError> {
    let atom = noun.in_space(space).as_atom()?;
    let bytes = atom.as_ne_bytes();
    let significant = bytes.iter().rposition(|b| *b != 0).map_or(0, |i| i + 1);
    if significant > 16 {
        return Err(NounDecodeError::Custom(
            "correlation id does not fit in 16 bytes".into(),
        ));
    }
    let mut le = [0u8; 16];
    le[..significant].copy_from_slice(&bytes[..significant]);
    Ok(IntentId::from_u128(u128::from_le_bytes(le)))
}

fn tas_noun<A: NounAllocator>(allocator: &mut A, text: &str) -> Noun {
    nockapp::utils::make_tas(allocator, text).as_noun()
}

fn string_noun<A: NounAllocator>(allocator: &mut A, text: &str) -> Noun {
    if text.is_empty() {
        D(0)
    } else {
        nockapp::utils::make_tas(allocator, text).as_noun()
    }
}

fn wire() -> WireRepr {
    WireRepr::new(WIRE_SOURCE, WIRE_VERSION, Vec::new())
}

/// Builds the NockApp IO driver.
///
/// Each `%tx %send` effect is handled on its own task, so a slow signer or a
/// long confirmation wait cannot stall the effect loop — which is what makes
/// having more than one payout in flight useful, and therefore what makes the
/// correlation id necessary.
///
/// Interrupted work from a previous run is recovered before the effect loop
/// starts, and those outcomes are poked back too, so a kernel learns the fate
/// of transactions it issued before the restart.
pub fn tx_driver(driver: Arc<TxDriver>) -> IODriverFn {
    make_driver(move |handle: NockAppHandle| async move {
        info!(
            journal = %driver.config().journal_dir.display(),
            dry_run = driver.config().dry_run,
            "transaction driver starting"
        );

        match driver.recover().await {
            Ok(outcomes) => {
                if !outcomes.is_empty() {
                    info!(count = outcomes.len(), "recovered interrupted transactions");
                }
                for outcome in &outcomes {
                    poke_outcome(&handle, outcome).await;
                }
            }
            Err(err) => {
                // Recovery failure must not take the driver down: new intents
                // are still serviceable, and the journal keeps the old ones.
                warn!("transaction driver recovery failed: {err}");
            }
        }

        let handle = Arc::new(handle);
        let mut tasks = tokio::task::JoinSet::new();

        loop {
            let effect = tokio::select! {
                effect = handle.next_effect() => effect,
                Some(finished) = tasks.join_next(), if !tasks.is_empty() => {
                    if let Err(err) = finished {
                        warn!("transaction task panicked: {err}");
                    }
                    continue;
                }
            };

            let Ok(effect) = effect else { continue };

            let decoded = {
                let noun = unsafe { effect.root() };
                let space = effect.noun_space();
                TxEffect::from_noun(noun, &space)
            };
            let effect = match decoded {
                Ok(effect) => effect,
                // Not ours, or a `%tx` verb we do not implement.
                Err(NounDecodeError::InvalidTag) => continue,
                Err(err) => {
                    warn!("failed to decode a %tx effect: {err}");
                    continue;
                }
            };

            let intent = effect.into_intent();
            debug!(intent = %intent.id, "accepted a %tx %send effect");

            let driver = Arc::clone(&driver);
            let handle = Arc::clone(&handle);
            tasks.spawn(async move {
                match driver.submit(intent).await {
                    Ok(outcome) => poke_outcome(&handle, &outcome).await,
                    Err(err) => warn!("transaction driver could not reach a verdict: {err}"),
                }
            });
        }
    })
}

async fn poke_outcome(handle: &NockAppHandle, outcome: &TxOutcome) {
    let slab = encode_cause(outcome);
    match handle.poke(wire(), slab).await {
        Ok(_) => debug!(intent = %outcome.id(), "poked transaction result back to the kernel"),
        Err(err) => warn!(
            intent = %outcome.id(),
            "failed to poke transaction result back to the kernel: {err}"
        ),
    }
}

#[cfg(test)]
mod tests {
    use nockchain_math::belt::Belt;
    use nockchain_types::tx_engine::common::{BlockHeight, Hash};

    use super::*;
    use crate::error::{RejectReason, TxDriverError};

    fn hash(seed: u64) -> Hash {
        Hash([Belt(seed + 1), Belt(seed + 2), Belt(seed + 3), Belt(seed + 4), Belt(seed + 5)])
    }

    /// Builds the noun a kernel would emit for `[%tx %send id src trg amount]`.
    fn send_effect_noun(
        slab: &mut NounSlab,
        id: u128,
        src: &SpendCondition,
        trg: &SpendCondition,
        amount: u64,
    ) -> Noun {
        let tx = tas_noun(slab, "tx");
        let send = tas_noun(slab, "send");
        let id = intent_id_noun(slab, IntentId::from_u128(id));
        let src = src.to_noun(slab);
        let trg = trg.to_noun(slab);
        let amount = amount.to_noun(slab);
        T(slab, &[tx, send, id, src, trg, amount])
    }

    #[test]
    fn a_send_effect_round_trips_into_an_intent() {
        let src = SpendCondition::simple_pkh(hash(1));
        let trg = SpendCondition::simple_pkh(hash(2));
        let mut slab: NounSlab = NounSlab::new();
        let noun = send_effect_noun(&mut slab, 0xdead_beef, &src, &trg, 100_000);
        slab.set_root(noun);

        let space = slab.noun_space();
        let root = unsafe { slab.root() };
        let effect = TxEffect::from_noun(root, &space).expect("decodes");

        assert_eq!(
            effect,
            TxEffect::Send {
                id: IntentId::from_u128(0xdead_beef),
                src_lock: src.clone(),
                trg_lock: trg.clone(),
                amount_nicks: 100_000,
            }
        );

        let intent = effect.into_intent();
        assert_eq!(intent.id, IntentId::from_u128(0xdead_beef));
        assert_eq!(intent.from, vec![src]);
        assert_eq!(intent.recipients.len(), 1);
        assert_eq!(
            intent.recipients[0].destination,
            crate::intent::Destination::Condition(trg)
        );
        assert_eq!(intent.recipients[0].amount_nicks, 100_000);
        // The key never appears anywhere in the effect.
        intent
            .validate()
            .expect("a decoded effect is a valid intent");
    }

    #[test]
    fn a_multisig_lock_survives_the_effect_encoding() {
        // The old protocol carried `src-pkh=@`, which could only name a simple
        // 1-of-1 lock. A full spend condition must survive the round trip or
        // the driver's lock support stops at the wire.
        let src = SpendCondition::new(vec![
            nockchain_types::tx_engine::v1::tx::LockPrimitive::Pkh(
                nockchain_types::tx_engine::v1::tx::Pkh::new(2, vec![hash(1), hash(2), hash(3)]),
            ),
        ]);
        let trg = SpendCondition::coinbase_pkh(hash(4), 100);
        let mut slab: NounSlab = NounSlab::new();
        let noun = send_effect_noun(&mut slab, 1, &src, &trg, 5);
        slab.set_root(noun);

        let space = slab.noun_space();
        let root = unsafe { slab.root() };
        match TxEffect::from_noun(root, &space).expect("decodes") {
            TxEffect::Send {
                src_lock, trg_lock, ..
            } => {
                assert_eq!(src_lock, src);
                assert_eq!(trg_lock, trg);
            }
        }
    }

    #[test]
    fn a_non_tx_effect_is_skipped_rather_than_failing() {
        let mut slab: NounSlab = NounSlab::new();
        let tag = tas_noun(&mut slab, "nockchain-grpc");
        let body = D(0);
        let noun = T(&mut slab, &[tag, body]);
        slab.set_root(noun);

        let space = slab.noun_space();
        let root = unsafe { slab.root() };
        assert!(matches!(
            TxEffect::from_noun(root, &space),
            Err(NounDecodeError::InvalidTag)
        ));
    }

    #[test]
    fn an_unknown_tx_verb_is_skipped_rather_than_failing() {
        let mut slab: NounSlab = NounSlab::new();
        let tx = tas_noun(&mut slab, "tx");
        let verb = tas_noun(&mut slab, "cancel");
        let noun = T(&mut slab, &[tx, verb, D(0)]);
        slab.set_root(noun);

        let space = slab.noun_space();
        let root = unsafe { slab.root() };
        assert!(matches!(
            TxEffect::from_noun(root, &space),
            Err(NounDecodeError::InvalidTag)
        ));
    }

    /// Reads back the tag and correlation id from an encoded cause.
    fn decode_cause(slab: &NounSlab) -> (String, u128) {
        let space = slab.noun_space();
        let root = unsafe { slab.root() };
        let cell = root.in_space(&space).as_cell().expect("cause is a cell");
        let tag = String::from_noun(&cell.head().noun(), &space).expect("tag decodes");
        let body = cell.tail().as_cell().expect("cause has a body");
        let id = intent_id_from_noun(&body.head().noun(), &space).expect("id decodes");
        (tag, id.as_u128())
    }

    #[test]
    fn every_cause_variant_echoes_the_correlation_id() {
        // The single most important property of this protocol.
        let id = IntentId::from_u128(0xabcd_1234);
        let tx_id = hash(9);
        let cases: Vec<(TxOutcome, &str)> = vec![
            (
                TxOutcome::Confirmed {
                    id,
                    tx_id: tx_id.clone(),
                    height: BlockHeight(Belt(42)),
                },
                "tx-confirmed",
            ),
            (
                TxOutcome::Submitted {
                    id,
                    tx_id: tx_id.clone(),
                },
                "tx-submitted",
            ),
            (TxOutcome::SignedNotSubmitted { id, tx_id }, "tx-signed"),
            (
                TxOutcome::Rejected {
                    id,
                    reason: RejectReason::MalformedIntent("no recipients".into()),
                    debug_trace: vec![],
                },
                "tx-rejected",
            ),
            (
                TxOutcome::Failed {
                    id,
                    error: TxDriverError::Chain("connection reset".into()),
                },
                "tx-failed",
            ),
        ];

        for (outcome, expected_tag) in cases {
            let slab = encode_cause(&outcome);
            let (tag, encoded_id) = decode_cause(&slab);
            assert_eq!(tag, expected_tag);
            assert_eq!(
                encoded_id, 0xabcd_1234,
                "the {expected_tag} cause dropped its correlation id"
            );
        }
    }

    #[test]
    fn rejection_and_failure_are_distinct_causes() {
        // A kernel must be able to tell "safe to roll back" from "status
        // unknown" without parsing an error string.
        let id = IntentId::from_u128(1);
        let rejected = encode_cause(&TxOutcome::Rejected {
            id,
            reason: RejectReason::MalformedIntent("x".into()),
            debug_trace: vec![],
        });
        let failed = encode_cause(&TxOutcome::Failed {
            id,
            error: TxDriverError::Chain("y".into()),
        });
        assert_eq!(decode_cause(&rejected).0, "tx-rejected");
        assert_eq!(decode_cause(&failed).0, "tx-failed");
    }

    #[test]
    fn concurrent_intents_produce_distinguishable_causes() {
        // Two payouts in flight: the exact scenario the old protocol could not
        // express, and which crashed a downstream kernel.
        let first = encode_cause(&TxOutcome::Confirmed {
            id: IntentId::from_u128(1),
            tx_id: hash(1),
            height: BlockHeight(Belt(10)),
        });
        let second = encode_cause(&TxOutcome::Confirmed {
            id: IntentId::from_u128(2),
            tx_id: hash(2),
            height: BlockHeight(Belt(10)),
        });
        assert_eq!(decode_cause(&first).1, 1);
        assert_eq!(decode_cause(&second).1, 2);
    }
}
