//! `tx-driver` — a transaction driver for Nockchain.
//!
//! Turns a declarative [`TxIntent`] into a confirmed on-chain transaction,
//! exactly once, with a typed [`TxOutcome`] correlated back to the caller.
//!
//! # Shape
//!
//! The core is a plain async library. It does not parse `argv`, does not own a
//! logging subscriber, and does not exit the process. A NockApp `IODriverFn`
//! adapter is available behind the `nockapp-driver` feature, and a CLI layer
//! belongs in a consumer binary. (The crate this replaces exported a clap
//! `Parser` that ran `Args::parse()` on the *host* binary's `argv`, which made
//! it unusable inside any app that had its own flags.)
//!
//! # Pipeline
//!
//! ```text
//! intent -> plan -> sign -> validate -> submit -> confirm
//!             |       |         |          |
//!             '-------'---------'----------'--- journalled at every step
//! ```
//!
//! Each stage is a separate module and a separate trait boundary where an
//! external authority is involved: [`chain::ChainSource`] for the network and
//! [`sign::Signer`] for key material. Neither the planner nor the driver ever
//! sees a private key.

// Tests use `unwrap` freely; a panic there is the failure signal.
#![cfg_attr(test, allow(clippy::unwrap_used))]

pub mod build;
pub mod chain;
pub mod driver;
pub mod error;
pub mod intent;
pub mod journal;
#[cfg(feature = "nockapp-driver")]
pub mod nockapp;
pub mod notes;
pub mod sign;
#[cfg(any(test, feature = "testing"))]
pub mod testing;

pub use chain::{BalanceSnapshot, ChainSource, GrpcChainSource, SubmitStatus};
pub use driver::{ConfirmPolicy, TxDriver, TxDriverConfig};
pub use error::{JournalError, RejectReason, Result, TxDriverError};
pub use intent::{FeePolicy, IntentId, NoteSelection, Recipient, TxIntent, TxOutcome};
pub use notes::{ClassifiedNotes, SpendConditionMatcher, UnlockContext, UnspendableReason};
pub use sign::{SignError, SignRequest, Signer};
