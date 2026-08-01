//! Transaction intents and their outcomes.
//!
//! An *intent* is a declarative statement of what the caller wants to happen:
//! who pays, who receives, how much. It deliberately does **not** carry a
//! private key. The driver this replaces passed `src-privkey` in-band through
//! the effect noun, which put the secret into kernel state, into on-disk
//! NockApp checkpoints, and into every log line that dumped the effect.
//! Here the spending authority is named by its
//! [`SpendCondition`], and the key material lives only inside a
//! [`crate::sign::Signer`].
//!
//! Every intent carries an [`IntentId`], and every outcome echoes it. That is
//! the correlation identifier whose absence made it impossible for a kernel
//! with more than one in-flight payout to match a result to a request.

use std::fmt;

use nockchain_types::tx_engine::common::{BlockHeight, Name, TxId};
use nockchain_types::tx_engine::v1::tx::SpendCondition;
use serde::{Deserialize, Serialize};

use crate::error::{RejectReason, TxDriverError};

/// An opaque 16-byte correlation identifier.
///
/// The driver never interprets the bytes. Callers that already have a request
/// id (a game id, a payout row id, a job uuid) should map it in here so that
/// outcomes can be joined back to their own state without a side table.
#[derive(Clone, Copy, PartialEq, Eq, Hash, PartialOrd, Ord, Serialize, Deserialize)]
pub struct IntentId(pub [u8; 16]);

impl IntentId {
    /// Builds an id from any byte slice by left-padding or truncating to 16
    /// bytes. Truncation is from the *left*, keeping the low-order bytes, which
    /// preserves uniqueness for counter-like ids.
    pub fn from_bytes(bytes: &[u8]) -> Self {
        let mut out = [0u8; 16];
        let n = bytes.len().min(16);
        out[16 - n..].copy_from_slice(&bytes[bytes.len() - n..]);
        Self(out)
    }

    /// Builds an id from a `u128`, the natural representation of the `@ux` the
    /// NockApp wire protocol carries.
    pub fn from_u128(value: u128) -> Self {
        Self(value.to_be_bytes())
    }

    /// The id as a `u128`, for encoding back onto the wire.
    pub fn as_u128(&self) -> u128 {
        u128::from_be_bytes(self.0)
    }

    /// Lowercase hex, used for journal filenames and log lines.
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
}

impl fmt::Display for IntentId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.to_hex())
    }
}

impl fmt::Debug for IntentId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "IntentId({})", self.to_hex())
    }
}

/// A single transaction output.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Recipient {
    /// The spend condition the output is locked to. Using a full
    /// [`SpendCondition`] rather than a bare public-key hash is what lets the
    /// driver pay into timelocked, hashlocked, and multisig outputs, not just
    /// simple 1-of-1 PKH ones.
    pub lock: SpendCondition,
    /// Amount in nicks. One NOCK is `wallet_tx_builder::fee::NICKS_PER_NOCK`.
    pub amount_nicks: u64,
}

impl Recipient {
    /// The common case: pay a single public-key hash.
    pub fn to_pkh(pkh: nockchain_types::tx_engine::common::Hash, amount_nicks: u64) -> Self {
        Self {
            lock: SpendCondition::simple_pkh(pkh),
            amount_nicks,
        }
    }
}

/// How the driver should choose the fee.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum FeePolicy {
    /// Let the planner compute the minimum viable fee for the assembled
    /// transaction. This runs the same two-pass estimate the wallet uses.
    #[default]
    Auto,
    /// Use the planner's estimate, but never less than this floor. Useful when
    /// a caller wants faster inclusion than the minimum buys.
    AtLeast(u64),
    /// Use exactly this fee. The driver still computes the minimum and rejects
    /// the intent if the exact fee is below it, rather than building a
    /// transaction that cannot be accepted.
    Exact(u64),
}

/// How the driver should choose which notes to spend.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub enum NoteSelection {
    /// Deterministic automatic selection, smallest-first by default.
    #[default]
    Auto,
    /// Deterministic automatic selection, largest-first. Produces fewer inputs
    /// and therefore a smaller fee, at the cost of fragmenting large notes.
    AutoLargestFirst,
    /// Spend exactly these notes and no others. If any is missing or
    /// unspendable the intent is rejected rather than silently falling back to
    /// automatic selection.
    Manual(Vec<Name>),
}

/// A declarative request to move value on chain.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TxIntent {
    /// Correlation id, echoed on every outcome.
    pub id: IntentId,
    /// The spend conditions whose notes may be used as inputs. Multiple entries
    /// let a single intent sweep across several locks the signer controls.
    pub from: Vec<SpendCondition>,
    /// Where the value goes.
    pub recipients: Vec<Recipient>,
    /// Where the remainder goes. Defaults to the first entry of `from`.
    pub refund_to: Option<SpendCondition>,
    /// Fee strategy.
    pub fee: FeePolicy,
    /// Input selection strategy.
    pub note_selection: NoteSelection,
    /// If set, the driver will not submit once the chain has passed this
    /// height, and will report [`RejectReason::DeadlineExpired`] instead. Only
    /// checked before submission — a deadline cannot un-submit a transaction.
    pub deadline: Option<BlockHeight>,
}

impl TxIntent {
    /// A single-sender, single-recipient payment with automatic fee and
    /// selection — the shape the old `[%tx %send ...]` effect encoded, minus
    /// the private key.
    pub fn simple_payment(
        id: IntentId,
        from: SpendCondition,
        to: SpendCondition,
        amount_nicks: u64,
    ) -> Self {
        Self {
            id,
            from: vec![from],
            recipients: vec![Recipient {
                lock: to,
                amount_nicks,
            }],
            refund_to: None,
            fee: FeePolicy::Auto,
            note_selection: NoteSelection::Auto,
            deadline: None,
        }
    }

    /// Total value requested by recipients, excluding fee. `None` on overflow,
    /// which is itself a malformed intent.
    pub fn total_recipient_amount(&self) -> Option<u64> {
        self.recipients
            .iter()
            .try_fold(0u64, |acc, r| acc.checked_add(r.amount_nicks))
    }

    /// The lock that receives the remainder.
    pub fn refund_lock(&self) -> Option<&SpendCondition> {
        self.refund_to.as_ref().or_else(|| self.from.first())
    }

    /// Structural validation that does not require chain state. Runs before any
    /// network call so that obviously-bad intents fail fast and terminally.
    pub fn validate(&self) -> std::result::Result<(), RejectReason> {
        if self.from.is_empty() {
            return Err(RejectReason::MalformedIntent(
                "intent has no source spend conditions".into(),
            ));
        }
        if self.recipients.is_empty() {
            return Err(RejectReason::MalformedIntent(
                "intent has no recipients".into(),
            ));
        }
        if self.recipients.iter().any(|r| r.amount_nicks == 0) {
            return Err(RejectReason::MalformedIntent(
                "intent has a zero-value recipient output".into(),
            ));
        }
        if self.total_recipient_amount().is_none() {
            return Err(RejectReason::MalformedIntent(
                "recipient amounts overflow u64".into(),
            ));
        }
        if let NoteSelection::Manual(names) = &self.note_selection {
            if names.is_empty() {
                return Err(RejectReason::MalformedIntent(
                    "manual note selection listed no notes".into(),
                ));
            }
        }
        Ok(())
    }
}

/// The terminal report for an intent.
///
/// Exactly one of these is delivered per intent, except that `Submitted` may be
/// delivered as a progress report and later superseded by `Confirmed` when the
/// caller has opted into confirmation tracking.
#[derive(Debug)]
pub enum TxOutcome {
    /// The transaction is on chain at the given height.
    Confirmed {
        id: IntentId,
        tx_id: TxId,
        height: BlockHeight,
    },
    /// The transaction was accepted into the mempool but is not yet in a block.
    /// The driver keeps the intent journalled and will keep resubmitting across
    /// restarts until it confirms or the caller abandons it.
    Submitted { id: IntentId, tx_id: TxId },
    /// Dry-run only: the transaction was built, signed, and validated, but
    /// deliberately not submitted, and deliberately **not** journalled — a
    /// journalled-but-unsubmitted intent would be resubmitted by recovery the
    /// next time the driver started for real.
    SignedNotSubmitted { id: IntentId, tx_id: TxId },
    /// Terminal. No spend derived from this intent can land. Safe to roll back.
    Rejected {
        id: IntentId,
        reason: RejectReason,
        /// The planner's decision trace when the rejection came from planning.
        /// Empty otherwise.
        debug_trace: Vec<String>,
    },
    /// Non-terminal. The driver could not finish; the spend's status is
    /// unknown. **Do not roll back on this.**
    Failed {
        id: IntentId,
        error: TxDriverError,
    },
}

impl TxOutcome {
    /// The correlation id, whichever variant this is.
    pub fn id(&self) -> IntentId {
        match self {
            Self::Confirmed { id, .. }
            | Self::Submitted { id, .. }
            | Self::SignedNotSubmitted { id, .. }
            | Self::Rejected { id, .. }
            | Self::Failed { id, .. } => *id,
        }
    }

    /// Whether the caller may safely undo optimistic local state.
    ///
    /// True only for `Rejected`. `Failed` is deliberately false: the driver does
    /// not know whether a spend is live, and a caller that rolls back here can
    /// double-spend its own ledger against a transaction that later confirms.
    pub fn is_safe_to_roll_back(&self) -> bool {
        matches!(self, Self::Rejected { .. })
    }

    /// The transaction id, once one exists.
    pub fn tx_id(&self) -> Option<&TxId> {
        match self {
            Self::Confirmed { tx_id, .. }
            | Self::Submitted { tx_id, .. }
            | Self::SignedNotSubmitted { tx_id, .. } => Some(tx_id),
            Self::Rejected { .. } | Self::Failed { .. } => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use nockchain_types::tx_engine::common::Hash;

    fn pkh(byte: u64) -> Hash {
        Hash([
            nockchain_math::belt::Belt(byte),
            nockchain_math::belt::Belt(0),
            nockchain_math::belt::Belt(0),
            nockchain_math::belt::Belt(0),
            nockchain_math::belt::Belt(0),
        ])
    }

    #[test]
    fn intent_id_round_trips_through_u128() {
        let id = IntentId::from_u128(0xdead_beef_1234_5678);
        assert_eq!(id.as_u128(), 0xdead_beef_1234_5678);
    }

    #[test]
    fn intent_id_from_short_slice_is_right_aligned() {
        let id = IntentId::from_bytes(&[0x01, 0x02]);
        assert_eq!(id.as_u128(), 0x0102);
    }

    #[test]
    fn intent_id_from_long_slice_keeps_low_order_bytes() {
        let mut long = vec![0xff; 20];
        long[19] = 0x07;
        let id = IntentId::from_bytes(&long);
        assert_eq!(id.0[15], 0x07);
    }

    #[test]
    fn empty_recipients_is_malformed() {
        let mut intent = TxIntent::simple_payment(
            IntentId::from_u128(1),
            SpendCondition::simple_pkh(pkh(1)),
            SpendCondition::simple_pkh(pkh(2)),
            100,
        );
        intent.recipients.clear();
        assert!(matches!(
            intent.validate(),
            Err(RejectReason::MalformedIntent(_))
        ));
    }

    #[test]
    fn zero_value_recipient_is_malformed() {
        let intent = TxIntent::simple_payment(
            IntentId::from_u128(1),
            SpendCondition::simple_pkh(pkh(1)),
            SpendCondition::simple_pkh(pkh(2)),
            0,
        );
        assert!(matches!(
            intent.validate(),
            Err(RejectReason::MalformedIntent(_))
        ));
    }

    #[test]
    fn overflowing_recipient_total_is_malformed() {
        let mut intent = TxIntent::simple_payment(
            IntentId::from_u128(1),
            SpendCondition::simple_pkh(pkh(1)),
            SpendCondition::simple_pkh(pkh(2)),
            u64::MAX,
        );
        intent.recipients.push(Recipient::to_pkh(pkh(3), 1));
        assert!(matches!(
            intent.validate(),
            Err(RejectReason::MalformedIntent(_))
        ));
    }

    #[test]
    fn refund_defaults_to_first_source_lock() {
        let from = SpendCondition::simple_pkh(pkh(1));
        let intent = TxIntent::simple_payment(
            IntentId::from_u128(1),
            from.clone(),
            SpendCondition::simple_pkh(pkh(2)),
            100,
        );
        assert_eq!(intent.refund_lock(), Some(&from));
    }

    #[test]
    fn only_rejected_is_safe_to_roll_back() {
        let id = IntentId::from_u128(1);
        let rejected = TxOutcome::Rejected {
            id,
            reason: RejectReason::MalformedIntent("x".into()),
            debug_trace: vec![],
        };
        let failed = TxOutcome::Failed {
            id,
            error: TxDriverError::Chain("connection reset".into()),
        };
        assert!(rejected.is_safe_to_roll_back());
        assert!(!failed.is_safe_to_roll_back());
    }
}
