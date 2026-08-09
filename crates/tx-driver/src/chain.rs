//! The driver's view of the network.
//!
//! Everything the driver needs from a Nockchain node sits behind
//! [`ChainSource`]: reading balances, reading the fee/timelock context, pushing
//! a signed transaction, and asking whether one was accepted. Isolating it
//! behind a trait is what makes the rest of the pipeline testable without a
//! node, and what lets a host swap in a light client later.
//!
//! [`GrpcChainSource`] is the production implementation. It talks to the **v2**
//! `public_nockchain` service, which is the one whose `wallet_send_transaction`
//! accepts a `v1::RawTx`; the v1 service is still on `v0::RawTx` and cannot
//! carry a witness-era transaction.

use async_trait::async_trait;
use nockapp::noun::slab::{NockJammer, NounSlab};
use nockchain_types::tx_engine::common::{BlockHeight, FirstName, Hash, Name, TxId};
use nockchain_types::tx_engine::v1;
use nockchain_types::BlockchainConstants;
use nockvm::noun::NounAllocator;
use noun_serde::{NounDecode, NounEncode};
use wallet_tx_builder::types::ChainContext;

use crate::error::{RejectReason, Result, TxDriverError};

/// A balance snapshot taken at a single block.
///
/// The `height`/`block_id` pair pins the snapshot: fee estimation and timelock
/// checks must be done against the same height the notes were read at, or a
/// note that looked spendable can be rejected by consensus.
#[derive(Debug, Clone)]
pub struct BalanceSnapshot {
    pub height: BlockHeight,
    pub block_id: Hash,
    pub notes: Vec<(Name, v1::Note)>,
}

impl BalanceSnapshot {
    pub fn is_empty(&self) -> bool {
        self.notes.is_empty()
    }

    pub fn total_assets(&self) -> u64 {
        self.notes
            .iter()
            .map(|(_, note)| note_assets(note))
            .fold(0u64, |acc, v| acc.saturating_add(v))
    }
}

/// Reads a note's asset value regardless of note version.
pub(crate) fn note_assets(note: &v1::Note) -> u64 {
    match note {
        v1::Note::V0(n) => n.tail.assets.0 as u64,
        v1::Note::V1(n) => n.assets.0 as u64,
    }
}

/// The result of pushing a transaction at the network.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SubmitStatus {
    /// The node took it. It is in the mempool, or was already there.
    Accepted,
    /// The node refused it outright, and told us why. Terminal: resubmitting
    /// identical bytes will get the same answer.
    Refused(String),
}

/// Everything the driver needs from a node.
#[async_trait]
pub trait ChainSource: Send + Sync {
    /// Reads every note locked to any of `first_names`, at a single consistent
    /// block. Implementations must not stitch together pages from different
    /// snapshots.
    async fn balance(&self, first_names: &[FirstName]) -> Result<BalanceSnapshot>;

    /// Reads the fee parameters and current height used by the planner.
    async fn chain_context(&self) -> Result<ChainContext>;

    /// Pushes a signed transaction. Must be idempotent with respect to
    /// resubmission of identical bytes: a transaction already in the mempool is
    /// [`SubmitStatus::Accepted`], not an error. The driver relies on this to
    /// recover from a crash between submitting and journalling the submission.
    async fn submit(&self, raw_tx: &v1::RawTx) -> Result<SubmitStatus>;

    /// Whether the node has accepted this transaction (mempool or chain).
    async fn accepted(&self, tx_id: &TxId) -> Result<bool>;

    /// The block a transaction landed in, if it has landed. `None` means "not
    /// in a block yet", which is distinct from "unknown transaction" — the
    /// latter is an error.
    async fn confirmed_at(&self, tx_id: &TxId) -> Result<Option<BlockHeight>>;
}

/// Production [`ChainSource`] over the v2 `public_nockchain` gRPC service.
#[derive(Clone)]
pub struct GrpcChainSource {
    client: nockapp_grpc::public_nockchain::v2::client::PublicNockchainGrpcClient,
    /// Fee parameters. Read once at connect time from the node's advertised
    /// constants, then refreshed alongside height on each `chain_context` call.
    constants: ChainConstants,
}

/// Fee and timelock constants the planner needs.
///
/// Split out from [`ChainContext`] because the height component changes every
/// block while these do not.
///
/// Getting these wrong is quiet and expensive: an underpriced transaction is
/// simply dropped by the network, with no error to observe from the client
/// side. Prefer [`ChainConstants::fetch_from_node`], which asks the node what
/// it is actually running, over [`ChainConstants::mainnet_defaults`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChainConstants {
    pub base_fee: u64,
    pub input_fee_divisor: u64,
    pub min_fee: u64,
    pub bythos_phase: BlockHeight,
    /// Relative timelock, in blocks, that marks a lock as coinbase-style.
    pub coinbase_relative_min: u64,
}

/// Peek path for the node's blockchain constants. Same path the bridge uses
/// (`crates/bridge/src/shared/nockchain.rs`) and the same one the wallet peeks
/// against its own kernel.
const BLOCKCHAIN_CONSTANTS_PATH: &str = "blockchain-constants";

/// Client pid for private-API peeks. The value is not interpreted by the node.
const PEEK_CLIENT_PID: i32 = 1;

impl ChainConstants {
    /// The compiled-in mainnet values.
    ///
    /// These come from `nockchain_types::BlockchainConstants`, which is the
    /// same source of truth the node's Hoon kernel is parameterised on, so they
    /// are right for a node running stock mainnet defaults — and wrong, in a
    /// way nothing will tell you about, for a fork or a devnet.
    pub fn mainnet_defaults() -> Self {
        Self::from_blockchain_constants(&BlockchainConstants::new())
    }

    /// Projects the node's full constants onto the subset the planner needs.
    ///
    /// `min_fee` comes from `note_data.min_fee`, matching how the wallet builds
    /// its `ChainContext` (`crates/nockchain-wallet/src/create_tx.rs:1578`). A
    /// different choice here would price transactions differently than the
    /// wallet does for the same inputs.
    pub fn from_blockchain_constants(constants: &BlockchainConstants) -> Self {
        Self {
            base_fee: constants.base_fee,
            input_fee_divisor: constants.input_fee_divisor,
            min_fee: constants.note_data.min_fee,
            bythos_phase: BlockHeight(nockchain_math::belt::Belt(constants.bythos_phase)),
            coinbase_relative_min: constants.coinbase_timelock_min,
        }
    }

    /// Reads the constants from a node over the **private** NockApp gRPC API.
    ///
    /// This is an arbitrary-peek admin interface, so it is normally only
    /// reachable on a node you run yourself. That is the intended deployment:
    /// a driver co-located with its node.
    ///
    /// Returns the node's full [`BlockchainConstants`] alongside the projection,
    /// so a caller can compare against its own expectations — see
    /// [`ChainConstants::fetch_from_node_checked`].
    pub async fn fetch_from_node(private_endpoint: &str) -> Result<(Self, BlockchainConstants)> {
        let mut client = nockapp_grpc::private_nockapp::client::PrivateNockAppGrpcClient::connect(
            private_endpoint,
        )
        .await
        .map_err(|err| {
            TxDriverError::Chain(format!(
                "connect to private endpoint {private_endpoint}: {err}"
            ))
        })?;

        let mut path_slab: NounSlab<NockJammer> = NounSlab::new();
        let path = vec![BLOCKCHAIN_CONSTANTS_PATH.to_string()].to_noun(&mut path_slab);
        path_slab.set_root(path);

        let response = client
            .peek(PEEK_CLIENT_PID, path_slab.jam().to_vec())
            .await
            .map_err(|err| TxDriverError::Chain(format!("blockchain-constants peek: {err}")))?;

        let constants = decode_blockchain_constants(response)?;
        Ok((Self::from_blockchain_constants(&constants), constants))
    }

    /// Reads the constants from a node and refuses to proceed if they differ
    /// from what the caller expected.
    ///
    /// This is the difference between "I priced the transaction correctly" and
    /// "I am talking to the chain I think I am". A node on a fork will happily
    /// serve balances and accept submissions; the constants are the cheapest
    /// place to notice. Mirrors `validate_blockchain_constants_match` in the
    /// bridge.
    pub async fn fetch_from_node_checked(
        private_endpoint: &str,
        expected: &BlockchainConstants,
    ) -> Result<Self> {
        let (projected, actual) = Self::fetch_from_node(private_endpoint).await?;
        if actual != *expected {
            return Err(TxDriverError::Config(format!(
                "node at {private_endpoint} reports blockchain constants that differ from the \
                 expected set; refusing to build transactions against an unknown chain. \
                 expected={expected:?} actual={actual:?}"
            )));
        }
        Ok(projected)
    }
}

fn decode_blockchain_constants(bytes: Vec<u8>) -> Result<BlockchainConstants> {
    let mut slab: NounSlab<NockJammer> = NounSlab::new();
    let noun = slab
        .cue_into(bytes::Bytes::from(bytes))
        .map_err(|err| TxDriverError::Noun(format!("blockchain-constants did not cue: {err}")))?;
    let space = slab.noun_space();
    let payload =
        Option::<Option<BlockchainConstants>>::from_noun(&noun, &space).map_err(|err| {
            TxDriverError::Noun(format!("blockchain-constants did not decode: {err}"))
        })?;
    payload.flatten().ok_or_else(|| {
        TxDriverError::Chain("node returned an empty blockchain-constants payload".into())
    })
}

impl GrpcChainSource {
    /// Connects to a node's public API using explicit fee constants.
    ///
    /// Prefer [`GrpcChainSource::connect_with_node`] when the driver runs
    /// alongside its own node, which is the intended deployment.
    pub async fn connect(endpoint: &str, constants: ChainConstants) -> Result<Self> {
        let client =
            nockapp_grpc::public_nockchain::v2::client::PublicNockchainGrpcClient::connect(
                endpoint,
            )
            .await
            .map_err(|err| TxDriverError::Chain(format!("connect to {endpoint}: {err}")))?;
        Ok(Self { client, constants })
    }

    /// Connects to a co-located node, reading fee constants from it rather than
    /// taking them on faith.
    ///
    /// `public_endpoint` serves balances and submissions; `private_endpoint` is
    /// the admin interface the constants peek needs. When `expected` is given,
    /// the node's constants must match it exactly or the connection fails.
    pub async fn connect_with_node(
        public_endpoint: &str,
        private_endpoint: &str,
        expected: Option<&BlockchainConstants>,
    ) -> Result<Self> {
        let constants = match expected {
            Some(expected) => {
                ChainConstants::fetch_from_node_checked(private_endpoint, expected).await?
            }
            None => ChainConstants::fetch_from_node(private_endpoint).await?.0,
        };
        tracing::info!(
            base_fee = constants.base_fee,
            input_fee_divisor = constants.input_fee_divisor,
            min_fee = constants.min_fee,
            bythos_phase = constants.bythos_phase.0 .0,
            "read fee constants from the node"
        );
        Self::connect(public_endpoint, constants).await
    }

    /// The constants this source was built with.
    pub fn constants(&self) -> &ChainConstants {
        &self.constants
    }
}

#[async_trait]
impl ChainSource for GrpcChainSource {
    async fn balance(&self, first_names: &[FirstName]) -> Result<BalanceSnapshot> {
        use nockapp_grpc::public_nockchain::v2::client::BalanceRequest;

        let mut client = self.client.clone();
        let mut notes: Vec<(Name, v1::Note)> = Vec::new();
        let mut pinned: Option<(BlockHeight, Hash)> = None;

        for first_name in first_names {
            let request = BalanceRequest::FirstName(first_name.to_base58());
            let balance = client
                .wallet_get_balance(&request)
                .await
                .map_err(|err| TxDriverError::Chain(format!("wallet_get_balance: {err}")))?;
            let update = v1::BalanceUpdate::try_from(balance).map_err(|err| {
                TxDriverError::Chain(format!("balance response did not convert: {err}"))
            })?;

            // Every first-name must be read at the same block, or fee and
            // timelock decisions are made against an inconsistent view.
            match &pinned {
                None => pinned = Some((update.height.clone(), update.block_id.clone())),
                Some((height, block_id)) => {
                    if *height != update.height || *block_id != update.block_id {
                        return Err(TxDriverError::Chain(
                            "balance snapshot changed between first-name queries; retry".into(),
                        ));
                    }
                }
            }
            notes.extend(update.notes.0);
        }

        let (height, block_id) = pinned
            .ok_or_else(|| TxDriverError::Chain("balance requested for zero first-names".into()))?;

        // The same note can be returned once per queried first-name when a
        // caller passes overlapping locks. Deduplicate on the full name.
        notes.sort_by(|(a, _), (b, _)| {
            a.first
                .to_array()
                .cmp(&b.first.to_array())
                .then_with(|| a.last.to_array().cmp(&b.last.to_array()))
        });
        notes.dedup_by(|(a, _), (b, _)| a == b);

        Ok(BalanceSnapshot {
            height,
            block_id,
            notes,
        })
    }

    async fn chain_context(&self) -> Result<ChainContext> {
        let mut client = self.client.clone();
        let height = client
            .explorer_heaviest_height()
            .await
            .map_err(|err| TxDriverError::Chain(format!("explorer_heaviest_height: {err}")))?;
        Ok(ChainContext {
            height: BlockHeight(nockchain_math::belt::Belt(height)),
            bythos_phase: self.constants.bythos_phase.clone(),
            base_fee: self.constants.base_fee,
            input_fee_divisor: self.constants.input_fee_divisor,
            min_fee: self.constants.min_fee,
        })
    }

    async fn submit(&self, raw_tx: &v1::RawTx) -> Result<SubmitStatus> {
        let mut client = self.client.clone();
        match client.wallet_send_transaction(raw_tx.clone()).await {
            Ok(_) => Ok(SubmitStatus::Accepted),
            Err(err) => classify_submit_error(&err.to_string()),
        }
    }

    async fn accepted(&self, tx_id: &TxId) -> Result<bool> {
        use nockapp_grpc::pb::common::v1::Base58Hash;
        use nockapp_grpc::pb::public::v2::transaction_accepted_response;

        let mut client = self.client.clone();
        let request = Base58Hash {
            hash: tx_id.to_base58(),
        };
        let response = client
            .transaction_accepted(request)
            .await
            .map_err(|err| TxDriverError::Chain(format!("transaction_accepted: {err}")))?;
        Ok(matches!(
            response.result,
            Some(transaction_accepted_response::Result::Accepted(true))
        ))
    }

    async fn confirmed_at(&self, tx_id: &TxId) -> Result<Option<BlockHeight>> {
        use nockapp_grpc::pb::common::v1::Base58Hash;

        let mut client = self.client.clone();
        let request = Base58Hash {
            hash: tx_id.to_base58(),
        };
        // The client already maps a NotFound status to `Ok(None)`, so an `Err`
        // here is a real transport or server fault, not "no such transaction".
        let block = client
            .get_transaction_block(request)
            .await
            .map_err(|err| TxDriverError::Chain(format!("get_transaction_block: {err}")))?;
        Ok(block.map(|(height, _block_id)| BlockHeight(nockchain_math::belt::Belt(height))))
    }
}

/// Decides whether a submission error is a terminal refusal or a transport
/// problem worth retrying.
///
/// Getting this wrong in either direction is costly: treating a transport blip
/// as a refusal abandons a transaction that may yet be valid, while treating a
/// validity refusal as a blip means resubmitting forever. The bias here is
/// deliberate — only errors that name a *validity* failure are terminal, and
/// everything else is returned as a retryable [`TxDriverError`], because
/// abandoning a good transaction is the less recoverable mistake.
fn classify_submit_error(message: &str) -> Result<SubmitStatus> {
    const TERMINAL_MARKERS: &[&str] = &[
        "invalid", "malformed", "double spend", "double-spend", "signature", "insufficient fee",
        "conflict", "rejected",
    ];
    let lowered = message.to_ascii_lowercase();
    if TERMINAL_MARKERS.iter().any(|m| lowered.contains(m)) {
        Ok(SubmitStatus::Refused(message.to_string()))
    } else {
        Err(TxDriverError::Chain(format!(
            "wallet_send_transaction: {message}"
        )))
    }
}

impl From<SubmitStatus> for std::result::Result<(), RejectReason> {
    fn from(status: SubmitStatus) -> Self {
        match status {
            SubmitStatus::Accepted => Ok(()),
            SubmitStatus::Refused(message) => Err(RejectReason::NetworkRefused(message)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mainnet_defaults_match_the_compiled_in_constants() {
        let constants = ChainConstants::mainnet_defaults();
        assert_eq!(constants.base_fee, BlockchainConstants::DEFAULT_BASE_FEE);
        assert_eq!(
            constants.input_fee_divisor,
            BlockchainConstants::DEFAULT_INPUT_FEE_DIVISOR
        );
        assert_eq!(
            constants.min_fee,
            BlockchainConstants::DEFAULT_NOTE_DATA_MIN_FEE
        );
        assert_eq!(
            constants.bythos_phase.0 .0,
            BlockchainConstants::DEFAULT_BYTHOS_PHASE
        );
        assert_eq!(
            constants.coinbase_relative_min,
            BlockchainConstants::DEFAULT_COINBASE_TIMELOCK_MIN
        );
    }

    #[test]
    fn min_fee_is_taken_from_note_data_not_invented() {
        // The wallet builds its ChainContext with `min_fee =
        // planner_constants.data.min_fee`
        // (crates/nockchain-wallet/src/create_tx.rs:1585). Taking it from
        // anywhere else would price the same transaction differently than the
        // wallet does, which is the kind of divergence that only shows up as a
        // silently dropped transaction.
        let mut constants = BlockchainConstants::new();
        constants.note_data.min_fee = 4_242;
        let projected = ChainConstants::from_blockchain_constants(&constants);
        assert_eq!(projected.min_fee, 4_242);
    }

    #[test]
    fn a_forked_constant_changes_the_projection() {
        // Guards against the projection quietly ignoring a field: if a fork
        // moves the Bythos activation height, the witness discount turns on at
        // a different block and every fee changes.
        let mut forked = BlockchainConstants::new();
        forked.bythos_phase = 999_999;
        let projected = ChainConstants::from_blockchain_constants(&forked);
        assert_ne!(projected, ChainConstants::mainnet_defaults());
        assert_eq!(projected.bythos_phase.0 .0, 999_999);
    }

    #[test]
    fn every_projected_field_is_load_bearing() {
        // Each field independently changes the projection, so none of them is
        // being silently dropped on the way through.
        let base = BlockchainConstants::new();
        let mutations: Vec<Box<dyn Fn(&mut BlockchainConstants)>> = vec![
            Box::new(|c: &mut BlockchainConstants| c.base_fee += 1),
            Box::new(|c: &mut BlockchainConstants| c.input_fee_divisor += 1),
            Box::new(|c: &mut BlockchainConstants| c.note_data.min_fee += 1),
            Box::new(|c: &mut BlockchainConstants| c.bythos_phase += 1),
            Box::new(|c: &mut BlockchainConstants| c.coinbase_timelock_min += 1),
        ];
        for (index, mutate) in mutations.iter().enumerate() {
            let mut mutated = base.clone();
            mutate(&mut mutated);
            assert_ne!(
                ChainConstants::from_blockchain_constants(&mutated),
                ChainConstants::from_blockchain_constants(&base),
                "projected field {index} is not load-bearing"
            );
        }
    }
}
