//! In-memory [`ChainSource`] and [`Signer`] implementations for tests.
//!
//! Available to downstream crates behind the `testing` feature so that e2e and
//! integration suites can drive the pipeline without a node or a wallet kernel.
//! The mock signer is faithful by default — it produces a transaction that
//! matches the plan exactly — and can be told to misbehave in specific ways, so
//! that the driver's defences against a bad signer are exercised by the same
//! code path as the good case.

use std::collections::BTreeMap;
use std::sync::Arc;

use async_trait::async_trait;
use nockchain_math::belt::Belt;
use nockchain_types::tx_engine::common::{
    BlockHeight, FirstName, Hash, Name, Nicks, TxId, Version,
};
use nockchain_types::tx_engine::v1;
use nockchain_types::tx_engine::v1::note::NoteData;
use nockchain_types::tx_engine::v1::tx::{
    LockMerkleProof, MerkleProof, PkhSignature, Seed, Seeds, Spend, Spend1, SpendCondition, Witness,
};
use tokio::sync::Mutex;
use wallet_tx_builder::types::ChainContext;

use crate::chain::{BalanceSnapshot, ChainSource, SubmitStatus};
use crate::error::{Result, TxDriverError};
use crate::sign::{SignError, SignRequest, Signer};

/// Builds a deterministic hash from a seed. Shared by tests so that the same
/// seed always names the same key, note, or lock root.
pub fn hash(seed: u64) -> Hash {
    Hash([
        Belt(seed + 1),
        Belt(seed + 2),
        Belt(seed + 3),
        Belt(seed + 4),
        Belt(seed + 5),
    ])
}

/// A note locked to `condition`, worth `assets` nicks, minted at `origin_page`.
pub fn note_for(
    condition: &SpendCondition,
    unique: u64,
    origin_page: u64,
    assets: u64,
) -> (Name, v1::Note) {
    let first = condition
        .first_name()
        .expect("spend condition hashes")
        .into_hash();
    let name = Name::new(first, hash(unique));
    let note = v1::Note::V1(v1::NoteV1 {
        version: Version::V1,
        origin_page: BlockHeight(Belt(origin_page)),
        name: name.clone(),
        note_data: NoteData(vec![]),
        assets: Nicks(assets as usize),
    });
    (name, note)
}

/// What the mock chain did, so tests can assert on it.
#[derive(Debug, Default, Clone)]
pub struct ChainLog {
    /// Every transaction handed to `submit`, in order, as jam bytes. Duplicate
    /// entries are how a test proves resubmission happened, and identical bytes
    /// are how it proves the same transaction was resubmitted.
    pub submissions: Vec<Vec<u8>>,
}

/// An in-memory chain.
pub struct MockChainSource {
    snapshot: Mutex<BalanceSnapshot>,
    context: ChainContext,
    log: Arc<Mutex<ChainLog>>,
    /// Height at which submitted transactions become confirmed. `None` leaves
    /// them permanently in the mempool.
    confirm_at: Option<BlockHeight>,
    /// When set, every submission is refused with this message.
    refuse_with: Option<String>,
    /// When set, every submission fails with a transport error instead.
    fail_transport: bool,
    accepted: Mutex<BTreeMap<[u64; 5], ()>>,
}

impl MockChainSource {
    /// A chain holding `notes` at `height`, with confirmations landing
    /// immediately.
    pub fn new(height: u64, notes: Vec<(Name, v1::Note)>) -> Self {
        Self {
            snapshot: Mutex::new(BalanceSnapshot {
                height: BlockHeight(Belt(height)),
                block_id: hash(7),
                notes,
            }),
            context: ChainContext {
                height: BlockHeight(Belt(height)),
                bythos_phase: BlockHeight(Belt(0)),
                base_fee: 10,
                input_fee_divisor: 2,
                min_fee: 100,
            },
            log: Arc::new(Mutex::new(ChainLog::default())),
            confirm_at: Some(BlockHeight(Belt(height + 1))),
            refuse_with: None,
            fail_transport: false,
            accepted: Mutex::new(BTreeMap::new()),
        }
    }

    /// Never confirms submitted transactions; they sit in the mempool.
    pub fn never_confirming(mut self) -> Self {
        self.confirm_at = None;
        self
    }

    /// Refuses every submission with `message`.
    pub fn refusing(mut self, message: impl Into<String>) -> Self {
        self.refuse_with = Some(message.into());
        self
    }

    /// Fails every submission with a transport error (non-terminal).
    pub fn with_transport_failure(mut self) -> Self {
        self.fail_transport = true;
        self
    }

    /// A handle to the submission log, cloneable across the `Arc<dyn
    /// ChainSource>` boundary.
    pub fn log(&self) -> Arc<Mutex<ChainLog>> {
        Arc::clone(&self.log)
    }
}

#[async_trait]
impl ChainSource for MockChainSource {
    async fn balance(&self, first_names: &[FirstName]) -> Result<BalanceSnapshot> {
        let snapshot = self.snapshot.lock().await;
        let wanted: Vec<[u64; 5]> = first_names.iter().map(|f| f.as_hash().to_array()).collect();
        Ok(BalanceSnapshot {
            height: snapshot.height.clone(),
            block_id: snapshot.block_id.clone(),
            notes: snapshot
                .notes
                .iter()
                .filter(|(name, _)| wanted.contains(&name.first.to_array()))
                .cloned()
                .collect(),
        })
    }

    async fn chain_context(&self) -> Result<ChainContext> {
        Ok(self.context.clone())
    }

    async fn submit(&self, raw_tx: &v1::RawTx) -> Result<SubmitStatus> {
        self.log
            .lock()
            .await
            .submissions
            .push(crate::journal::jam_raw_tx(raw_tx));

        if self.fail_transport {
            return Err(TxDriverError::Chain("connection reset by peer".into()));
        }
        if let Some(message) = &self.refuse_with {
            return Ok(SubmitStatus::Refused(message.clone()));
        }
        self.accepted.lock().await.insert(raw_tx.id.to_array(), ());
        Ok(SubmitStatus::Accepted)
    }

    async fn accepted(&self, tx_id: &TxId) -> Result<bool> {
        Ok(self.accepted.lock().await.contains_key(&tx_id.to_array()))
    }

    async fn confirmed_at(&self, tx_id: &TxId) -> Result<Option<BlockHeight>> {
        if !self.accepted.lock().await.contains_key(&tx_id.to_array()) {
            return Ok(None);
        }
        Ok(self.confirm_at.clone())
    }
}

/// How a mock signer should misbehave.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SignerBehaviour {
    /// Sign exactly what was planned.
    Faithful,
    /// Redirect every output to `lock_root`.
    RedirectOutputs { lock_root: Hash },
    /// Charge `fee` instead of the planned one.
    InflateFee { fee: u64 },
    /// Add an output paying `lock_root` `amount` nicks.
    AddOutput { lock_root: Hash, amount: u64 },
    /// Refuse, terminally.
    Decline(String),
    /// Fail, non-terminally.
    Unavailable(String),
}

/// A signer that builds a transaction directly from the plan.
pub struct MockSigner {
    pkhs: Vec<Hash>,
    behaviour: SignerBehaviour,
    calls: Arc<Mutex<Vec<SignRequest>>>,
}

impl MockSigner {
    pub fn new(pkhs: Vec<Hash>) -> Self {
        Self {
            pkhs,
            behaviour: SignerBehaviour::Faithful,
            calls: Arc::new(Mutex::new(Vec::new())),
        }
    }

    pub fn behaving(mut self, behaviour: SignerBehaviour) -> Self {
        self.behaviour = behaviour;
        self
    }

    /// Every request this signer has been given.
    pub fn calls(&self) -> Arc<Mutex<Vec<SignRequest>>> {
        Arc::clone(&self.calls)
    }
}

#[async_trait]
impl Signer for MockSigner {
    async fn signer_pkhs(&self) -> std::result::Result<Vec<Hash>, SignError> {
        Ok(self.pkhs.clone())
    }

    async fn sign(&self, request: SignRequest) -> std::result::Result<v1::RawTx, SignError> {
        match &self.behaviour {
            SignerBehaviour::Decline(message) => {
                return Err(SignError::Declined(message.clone()))
            }
            SignerBehaviour::Unavailable(message) => {
                return Err(SignError::Unavailable(message.clone()))
            }
            _ => {}
        }

        let plan = request.plan.clone();
        self.calls.lock().await.push(request);

        let mut outputs: Vec<(Hash, u64)> = plan
            .assembled
            .outputs
            .iter()
            .map(|o| (o.lock_root.clone(), o.amount))
            .collect();
        let mut fee = plan.assembled.fee;

        match &self.behaviour {
            SignerBehaviour::RedirectOutputs { lock_root } => {
                for output in &mut outputs {
                    output.0 = lock_root.clone();
                }
            }
            SignerBehaviour::InflateFee { fee: inflated } => fee = *inflated,
            SignerBehaviour::AddOutput { lock_root, amount } => {
                outputs.push((lock_root.clone(), *amount))
            }
            _ => {}
        }

        // All seeds ride on the first spend; the driver aggregates across
        // spends, so this is a legitimate arrangement.
        let mut spends = Vec::with_capacity(plan.assembled.inputs.len());
        for (index, input) in plan.assembled.inputs.iter().enumerate() {
            let seeds = if index == 0 {
                Seeds(
                    outputs
                        .iter()
                        .map(|(lock_root, amount)| Seed {
                            output_source: None,
                            lock_root: lock_root.clone(),
                            note_data: NoteData(vec![]),
                            gift: Nicks(*amount as usize),
                            parent_hash: input.note.name.first.clone(),
                        })
                        .collect(),
                )
            } else {
                Seeds(vec![])
            };
            let spend_fee = if index == 0 { fee } else { 0 };
            spends.push((
                input.note.name.clone(),
                Spend::Witness(Spend1 {
                    witness: Witness {
                        lock_merkle_proof: LockMerkleProof::new_stub(
                            input.lock.clone(),
                            1,
                            MerkleProof {
                                root: hash(2),
                                path: vec![],
                            },
                        ),
                        pkh_signature: PkhSignature(vec![]),
                        hax: vec![],
                        tim: 0,
                    },
                    seeds,
                    fee: Nicks(spend_fee as usize),
                }),
            ));
        }

        let mut tx = v1::RawTx {
            version: Version::V1,
            id: hash(0),
            spends: v1::Spends(spends),
        };
        tx.id = tx
            .compute_id()
            .map_err(|err| SignError::Undecodable(err.to_string()))?;
        Ok(tx)
    }
}
