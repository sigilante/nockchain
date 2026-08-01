//! Error taxonomy for the transaction driver.
//!
//! The central distinction is between [`RejectReason`] and [`TxDriverError`]:
//!
//! - A [`RejectReason`] is **terminal**. It can only be produced before a
//!   transaction is submitted to the network, and it proves that no spend
//!   deriving from this intent can ever land on chain. A caller that debited
//!   local state optimistically may safely roll that debit back.
//! - A [`TxDriverError`] is **non-terminal**. It says the driver could not
//!   complete the pipeline, but says nothing about whether a spend is live. A
//!   caller must *not* roll back on this; it must reconcile against chain state.
//!
//! The reconstructed `tx-driver` collapsed both into a single `[%tx-fail
//! error=@t]` cause, so a caller had no protocol-level way to tell a dead
//! spend from a merely unconfirmed one. Keeping the two apart in the type
//! system is the fix.

use nockchain_types::tx_engine::common::{BlockHeight, Name};

/// A terminal, pre-submission rejection.
///
/// Every variant here is a proof that the intent cannot produce an on-chain
/// spend. Never constructed after a successful network submission.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RejectReason {
    /// The spendable balance is below the requested amount plus the computed fee.
    #[error("insufficient funds: need {needed} nicks (amount + fee), have {available} nicks spendable")]
    InsufficientFunds { needed: u64, available: u64 },

    /// The intent named notes that the balance snapshot does not contain.
    #[error("unknown note {}", .0.first.to_base58())]
    UnknownNote(Box<Name>),

    /// The intent named notes the driver cannot unlock. Carries the same typed
    /// reasons reported by [`crate::notes::UnspendableReason`].
    #[error("{count} selected note(s) are not spendable by this driver")]
    NotesUnspendable { count: usize },

    /// The planner refused the request. Carries the planner's own message plus
    /// its decision trace, which is the only way to debug a selection failure.
    #[error("planner rejected the request: {message}")]
    PlanRejected {
        message: String,
        debug_trace: Vec<String>,
    },

    /// The intent asked for an output the transaction engine cannot express.
    #[error("malformed intent: {0}")]
    MalformedIntent(String),

    /// The signer declined to sign — a user hit "reject" in a wallet prompt, a
    /// hardware device refused, a policy engine said no.
    #[error("signer declined to sign: {0}")]
    SignerDeclined(String),

    /// The signer returned a transaction that does not match what the driver
    /// planned. Treated as terminal on purpose: the driver will not submit a
    /// transaction it cannot account for, and it will not retry, because a
    /// signer that returns the wrong thing once will do so again.
    #[error("signer returned a transaction that does not match the plan: {0}")]
    SignerMismatch(String),

    /// The intent's deadline passed before the driver could submit.
    #[error("deadline of block {} passed before submission (chain is at {})", deadline.0 .0, current.0 .0)]
    DeadlineExpired {
        deadline: BlockHeight,
        current: BlockHeight,
    },

    /// The network rejected the transaction outright at submission time. This is
    /// the one post-`submit()` variant, and it is terminal only because the node
    /// told us the transaction was never admitted to the mempool.
    #[error("network refused the transaction: {0}")]
    NetworkRefused(String),
}

/// A non-terminal driver failure. The spend's status is unknown.
#[derive(Debug, thiserror::Error)]
pub enum TxDriverError {
    #[error("chain source error: {0}")]
    Chain(String),

    #[error("signer error: {0}")]
    Signer(String),

    #[error("journal error: {0}")]
    Journal(#[from] JournalError),

    #[error("failed to encode or decode a noun: {0}")]
    Noun(String),

    #[error("transaction id could not be computed: {0}")]
    TxId(String),

    #[error("the driver was shut down while intent {0} was in flight")]
    ShuttingDown(crate::intent::IntentId),

    #[error("configuration error: {0}")]
    Config(String),

    #[error(transparent)]
    Io(#[from] std::io::Error),
}

/// Failures of the durable journal.
///
/// These are separated out because a journal failure is the one class of error
/// that compromises the driver's exactly-once guarantee, and callers may want to
/// treat it as fatal rather than merely non-terminal.
#[derive(Debug, thiserror::Error)]
pub enum JournalError {
    #[error("journal io error at {path}: {source}")]
    Io {
        path: String,
        #[source]
        source: std::io::Error,
    },

    #[error("journal record {offset} is corrupt: {message}")]
    Corrupt { offset: u64, message: String },

    #[error("journal records an impossible transition for intent {intent}: {from} -> {to}")]
    IllegalTransition {
        intent: crate::intent::IntentId,
        from: &'static str,
        to: &'static str,
    },
}

/// Convenience alias used throughout the crate.
pub type Result<T> = std::result::Result<T, TxDriverError>;
