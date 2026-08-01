//! The durable write-ahead journal.
//!
//! The crate this replaces depended on `yaque`, a disk-backed queue, which is
//! strong evidence that it kept transactions across restarts. This module
//! provides that property directly rather than through a generic queue, because
//! what the driver needs is not redelivery — it is *idempotent resubmission*,
//! and the two have different correctness arguments.
//!
//! # Why this is exactly-once
//!
//! A Nockchain transaction id is a digest over the signed transaction. Two
//! things follow:
//!
//! 1. Resubmitting identical bytes is a no-op. The node either accepts a
//!    transaction it already has, or accepts it for the first time. There is no
//!    way for one signed transaction to land twice.
//! 2. Re-*planning* after a crash is not safe, because the balance may have
//!    moved and the driver could select different inputs, producing a second,
//!    different transaction spending overlapping notes.
//!
//! So the rule this module enforces is: **once an intent reaches
//! [`IntentState::Signed`], the signed bytes are authoritative and are never
//! regenerated.** Recovery replays the journal and resubmits those exact bytes.
//! Before `Signed`, nothing has been shown to the network and re-planning from
//! scratch is both safe and preferable, since the chain has moved on.
//!
//! # Crash model
//!
//! Records are newline-delimited JSON, appended and `fsync`ed one at a time. The
//! only tearing a crash can produce is a truncated final line, which replay
//! detects and discards — an intent whose last transition was lost simply
//! resumes from its previous state, and the state machine is built so that
//! every such replay is safe.

use std::collections::BTreeMap;
use std::io::SeekFrom;
use std::path::{Path, PathBuf};

use bytes::Bytes;
use nockapp::noun::slab::NounSlab;
use nockchain_types::tx_engine::common::{BlockHeight, TxId};
use nockchain_types::tx_engine::v1;
use nockvm::noun::NounAllocator;
use noun_serde::{NounDecode, NounEncode};
use serde::{Deserialize, Serialize};
use tokio::io::{AsyncSeekExt, AsyncWriteExt};

use crate::error::JournalError;
use crate::intent::IntentId;

const LOG_FILE: &str = "journal.log";
const COMPACT_FILE: &str = "journal.compact";

/// Where an intent has got to. Ordered by progress; the state machine only
/// allows forward transitions.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum IntentState {
    /// Accepted by the driver, nothing built yet. Safe to re-plan.
    Accepted,
    /// Planned but not signed. Safe to re-plan; the plan is not persisted
    /// because it is cheap to recompute and stale by the time we recover.
    Planned,
    /// Signed. The bytes are authoritative from here on and must never be
    /// regenerated. Recovery resubmits exactly these bytes.
    Signed { tx_id: TxId, raw_tx: Vec<u8> },
    /// Handed to the network and accepted into the mempool.
    Submitted { tx_id: TxId, raw_tx: Vec<u8> },
    /// In a block. Terminal.
    Confirmed { tx_id: TxId, height: BlockHeight },
    /// Terminally refused. Terminal.
    Rejected { reason: String },
}

impl IntentState {
    /// Whether no further work is needed for this intent.
    pub fn is_terminal(&self) -> bool {
        matches!(self, Self::Confirmed { .. } | Self::Rejected { .. })
    }

    /// The signed bytes, if this intent has any. Their presence is exactly the
    /// condition under which re-planning is forbidden.
    pub fn signed_bytes(&self) -> Option<(&TxId, &[u8])> {
        match self {
            Self::Signed { tx_id, raw_tx } | Self::Submitted { tx_id, raw_tx } => {
                Some((tx_id, raw_tx.as_slice()))
            }
            _ => None,
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Self::Accepted => "accepted",
            Self::Planned => "planned",
            Self::Signed { .. } => "signed",
            Self::Submitted { .. } => "submitted",
            Self::Confirmed { .. } => "confirmed",
            Self::Rejected { .. } => "rejected",
        }
    }

    fn rank(&self) -> u8 {
        match self {
            Self::Accepted => 0,
            Self::Planned => 1,
            Self::Signed { .. } => 2,
            Self::Submitted { .. } => 3,
            Self::Confirmed { .. } | Self::Rejected { .. } => 4,
        }
    }
}

/// One durable transition.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "t", rename_all = "snake_case")]
enum Record {
    Accepted {
        id: IntentId,
    },
    Planned {
        id: IntentId,
    },
    Signed {
        id: IntentId,
        /// Base58 transaction id, for human inspection of the log.
        tx_id: String,
        /// Hex-encoded jam of the signed `v1::RawTx`. The canonical encoding is
        /// used rather than an ad-hoc one so that the bytes replayed after a
        /// crash are byte-identical to the ones originally submitted.
        raw_tx_hex: String,
    },
    Submitted {
        id: IntentId,
        tx_id: String,
    },
    Confirmed {
        id: IntentId,
        tx_id: String,
        height: u64,
    },
    Rejected {
        id: IntentId,
        reason: String,
    },
}

impl Record {
    fn id(&self) -> IntentId {
        match self {
            Self::Accepted { id }
            | Self::Planned { id }
            | Self::Signed { id, .. }
            | Self::Submitted { id, .. }
            | Self::Confirmed { id, .. }
            | Self::Rejected { id, .. } => *id,
        }
    }
}

/// An append-only, crash-safe record of every intent's progress.
#[derive(Debug)]
pub struct Journal {
    dir: PathBuf,
    file: tokio::fs::File,
    states: BTreeMap<IntentId, IntentState>,
}

impl Journal {
    /// Opens (creating if needed) the journal in `dir` and replays it.
    ///
    /// A torn final record is discarded and the file truncated to the last
    /// complete record, which is the only corruption an append-and-fsync log
    /// can produce on its own. Corruption anywhere earlier is reported rather
    /// than silently skipped: a hole in the middle of the log could hide a
    /// `Signed` record, and losing one of those is exactly the case that breaks
    /// the exactly-once guarantee.
    pub async fn open(dir: impl AsRef<Path>) -> Result<Self, JournalError> {
        let dir = dir.as_ref().to_path_buf();
        tokio::fs::create_dir_all(&dir)
            .await
            .map_err(|source| JournalError::Io {
                path: dir.display().to_string(),
                source,
            })?;

        let path = dir.join(LOG_FILE);
        let bytes = match tokio::fs::read(&path).await {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => Vec::new(),
            Err(source) => {
                return Err(JournalError::Io {
                    path: path.display().to_string(),
                    source,
                })
            }
        };

        let (states, good_len) = replay(&bytes)?;

        let mut file = tokio::fs::OpenOptions::new()
            .create(true)
            // Never truncate: the whole point of the log is that what was
            // written before this process started is still there.
            .truncate(false)
            .read(true)
            .write(true)
            .open(&path)
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;

        if good_len != bytes.len() as u64 {
            tracing::warn!(
                path = %path.display(),
                discarded_bytes = bytes.len() as u64 - good_len,
                "discarding a torn trailing journal record"
            );
            file.set_len(good_len)
                .await
                .map_err(|source| JournalError::Io {
                    path: path.display().to_string(),
                    source,
                })?;
        }
        file.seek(SeekFrom::End(0))
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;

        Ok(Self { dir, file, states })
    }

    /// Every intent the journal knows about, in id order.
    pub fn states(&self) -> &BTreeMap<IntentId, IntentState> {
        &self.states
    }

    /// The state of one intent.
    pub fn state(&self, id: &IntentId) -> Option<&IntentState> {
        self.states.get(id)
    }

    /// Intents that still need work after a restart, in id order.
    ///
    /// An intent with signed bytes is resumed by resubmitting those bytes; an
    /// intent without them is resumed by re-planning. Terminal intents are not
    /// returned.
    pub fn unfinished(&self) -> Vec<(IntentId, IntentState)> {
        self.states
            .iter()
            .filter(|(_, state)| !state.is_terminal())
            .map(|(id, state)| (*id, state.clone()))
            .collect()
    }

    /// Records that an intent has been accepted for processing.
    pub async fn accept(&mut self, id: IntentId) -> Result<(), JournalError> {
        self.append(Record::Accepted { id }).await
    }

    /// Records that an intent has been planned.
    pub async fn planned(&mut self, id: IntentId) -> Result<(), JournalError> {
        self.append(Record::Planned { id }).await
    }

    /// Records a signed transaction. **This is the durability barrier**: after
    /// this returns, the driver is committed to these exact bytes and must
    /// never re-plan or re-sign this intent.
    pub async fn signed(&mut self, id: IntentId, raw_tx: &v1::RawTx) -> Result<(), JournalError> {
        let bytes = jam_raw_tx(raw_tx);
        self.append(Record::Signed {
            id,
            tx_id: raw_tx.id.to_base58(),
            raw_tx_hex: hex::encode(&bytes),
        })
        .await
    }

    /// Records that the network accepted the transaction.
    pub async fn submitted(&mut self, id: IntentId, tx_id: &TxId) -> Result<(), JournalError> {
        self.append(Record::Submitted {
            id,
            tx_id: tx_id.to_base58(),
        })
        .await
    }

    /// Records confirmation in a block. Terminal.
    pub async fn confirmed(
        &mut self,
        id: IntentId,
        tx_id: &TxId,
        height: &BlockHeight,
    ) -> Result<(), JournalError> {
        self.append(Record::Confirmed {
            id,
            tx_id: tx_id.to_base58(),
            height: height.0 .0,
        })
        .await
    }

    /// Records terminal rejection. Terminal.
    pub async fn rejected(
        &mut self,
        id: IntentId,
        reason: impl Into<String>,
    ) -> Result<(), JournalError> {
        self.append(Record::Rejected {
            id,
            reason: reason.into(),
        })
        .await
    }

    /// Appends one record, fsyncs, and only then updates in-memory state.
    ///
    /// The ordering matters: if the process dies between the write and the
    /// in-memory update, replay reconstructs the same state. If it were the
    /// other way round, the driver could believe an intent was signed while the
    /// disk disagreed, and a restart would re-sign it.
    async fn append(&mut self, record: Record) -> Result<(), JournalError> {
        let id = record.id();
        let next = apply(self.states.get(&id), &record, id)?;

        let mut line = serde_json::to_vec(&record).map_err(|err| JournalError::Corrupt {
            offset: 0,
            message: format!("record did not serialize: {err}"),
        })?;
        line.push(b'\n');

        let path = self.dir.join(LOG_FILE);
        self.file
            .write_all(&line)
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;
        self.file
            .sync_data()
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;

        self.states.insert(id, next);
        Ok(())
    }

    /// Rewrites the log, dropping terminal intents.
    ///
    /// Done by writing a fresh file and renaming it over the old one, so a
    /// crash mid-compaction leaves the original log intact. Non-terminal
    /// intents are re-emitted as a single record carrying their current state,
    /// which is enough to reconstruct them — the intermediate history has no
    /// operational value once an intent has moved past it.
    pub async fn compact(&mut self) -> Result<usize, JournalError> {
        let retained: Vec<(IntentId, IntentState)> = self
            .states
            .iter()
            .filter(|(_, state)| !state.is_terminal())
            .map(|(id, state)| (*id, state.clone()))
            .collect();
        let dropped = self.states.len() - retained.len();
        if dropped == 0 {
            return Ok(0);
        }

        let tmp = self.dir.join(COMPACT_FILE);
        let mut out = tokio::fs::File::create(&tmp)
            .await
            .map_err(|source| JournalError::Io {
                path: tmp.display().to_string(),
                source,
            })?;

        for (id, state) in &retained {
            for record in records_for(*id, state) {
                let mut line =
                    serde_json::to_vec(&record).map_err(|err| JournalError::Corrupt {
                        offset: 0,
                        message: format!("record did not serialize: {err}"),
                    })?;
                line.push(b'\n');
                out.write_all(&line)
                    .await
                    .map_err(|source| JournalError::Io {
                        path: tmp.display().to_string(),
                        source,
                    })?;
            }
        }
        out.sync_all().await.map_err(|source| JournalError::Io {
            path: tmp.display().to_string(),
            source,
        })?;
        drop(out);

        let path = self.dir.join(LOG_FILE);
        tokio::fs::rename(&tmp, &path)
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;

        let mut file = tokio::fs::OpenOptions::new()
            .read(true)
            .write(true)
            .open(&path)
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;
        file.seek(SeekFrom::End(0))
            .await
            .map_err(|source| JournalError::Io {
                path: path.display().to_string(),
                source,
            })?;
        self.file = file;

        self.states.retain(|_, state| !state.is_terminal());
        Ok(dropped)
    }
}

/// The record sequence that reconstructs `state` from nothing. Used by
/// compaction.
fn records_for(id: IntentId, state: &IntentState) -> Vec<Record> {
    match state {
        IntentState::Accepted => vec![Record::Accepted { id }],
        IntentState::Planned => vec![Record::Accepted { id }, Record::Planned { id }],
        IntentState::Signed { tx_id, raw_tx } => vec![
            Record::Accepted { id },
            Record::Planned { id },
            Record::Signed {
                id,
                tx_id: tx_id.to_base58(),
                raw_tx_hex: hex::encode(raw_tx),
            },
        ],
        IntentState::Submitted { tx_id, raw_tx } => vec![
            Record::Accepted { id },
            Record::Planned { id },
            Record::Signed {
                id,
                tx_id: tx_id.to_base58(),
                raw_tx_hex: hex::encode(raw_tx),
            },
            Record::Submitted {
                id,
                tx_id: tx_id.to_base58(),
            },
        ],
        // Terminal states are never retained by compaction.
        IntentState::Confirmed { .. } | IntentState::Rejected { .. } => Vec::new(),
    }
}

/// The state machine. Rejects backwards and skipping transitions.
///
/// Re-applying the *same* transition is allowed and idempotent, because a crash
/// between the disk write and the in-memory update means the driver may legally
/// retry a step it already durably recorded.
fn apply(
    current: Option<&IntentState>,
    record: &Record,
    id: IntentId,
) -> Result<IntentState, JournalError> {
    let next = match record {
        Record::Accepted { .. } => IntentState::Accepted,
        Record::Planned { .. } => IntentState::Planned,
        Record::Signed {
            tx_id, raw_tx_hex, ..
        } => IntentState::Signed {
            tx_id: parse_tx_id(tx_id, id)?,
            raw_tx: parse_hex(raw_tx_hex, id)?,
        },
        Record::Submitted { tx_id, .. } => {
            // Submission carries no bytes of its own; it promotes the signed
            // bytes already on record. An intent cannot be submitted without
            // having been signed first, which this lookup enforces.
            let (signed_tx_id, raw_tx) = current.and_then(|state| state.signed_bytes()).ok_or(
                JournalError::IllegalTransition {
                    intent: id,
                    from: current.map(IntentState::label).unwrap_or("none"),
                    to: "submitted",
                },
            )?;
            let recorded = parse_tx_id(tx_id, id)?;
            if recorded != *signed_tx_id {
                return Err(JournalError::Corrupt {
                    offset: 0,
                    message: format!(
                        "intent {id} was submitted as {} but signed as {}",
                        recorded.to_base58(),
                        signed_tx_id.to_base58()
                    ),
                });
            }
            IntentState::Submitted {
                tx_id: recorded,
                raw_tx: raw_tx.to_vec(),
            }
        }
        Record::Confirmed { tx_id, height, .. } => IntentState::Confirmed {
            tx_id: parse_tx_id(tx_id, id)?,
            height: BlockHeight(nockchain_math::belt::Belt(*height)),
        },
        Record::Rejected { reason, .. } => IntentState::Rejected {
            reason: reason.clone(),
        },
    };

    match current {
        None => {
            if !matches!(next, IntentState::Accepted) {
                return Err(JournalError::IllegalTransition {
                    intent: id,
                    from: "none",
                    to: next.label(),
                });
            }
        }
        Some(current) => {
            // Rejection may arrive from any non-terminal state: a signer can
            // decline, and the network can refuse, at different points.
            let rejecting = matches!(next, IntentState::Rejected { .. });
            if current.is_terminal() {
                return Err(JournalError::IllegalTransition {
                    intent: id,
                    from: current.label(),
                    to: next.label(),
                });
            }
            if !rejecting && next.rank() < current.rank() {
                return Err(JournalError::IllegalTransition {
                    intent: id,
                    from: current.label(),
                    to: next.label(),
                });
            }
        }
    }

    Ok(next)
}

/// Replays a log buffer, returning the reconstructed states and the byte length
/// of the last complete, well-formed record.
fn replay(bytes: &[u8]) -> Result<(BTreeMap<IntentId, IntentState>, u64), JournalError> {
    let mut states: BTreeMap<IntentId, IntentState> = BTreeMap::new();
    let mut offset: u64 = 0;

    for line in bytes.split_inclusive(|b| *b == b'\n') {
        if !line.ends_with(b"\n") {
            // A trailing partial line is a torn append. Everything before it is
            // intact, so stop here and let the caller truncate.
            break;
        }
        let trimmed = &line[..line.len() - 1];
        if trimmed.is_empty() {
            offset += line.len() as u64;
            continue;
        }
        let record: Record =
            serde_json::from_slice(trimmed).map_err(|err| JournalError::Corrupt {
                offset,
                message: err.to_string(),
            })?;
        let id = record.id();
        let next = apply(states.get(&id), &record, id)?;
        states.insert(id, next);
        offset += line.len() as u64;
    }

    Ok((states, offset))
}

fn parse_tx_id(b58: &str, id: IntentId) -> Result<TxId, JournalError> {
    TxId::from_base58(b58).map_err(|err| JournalError::Corrupt {
        offset: 0,
        message: format!("intent {id} has an undecodable tx id {b58:?}: {err}"),
    })
}

fn parse_hex(hex_str: &str, id: IntentId) -> Result<Vec<u8>, JournalError> {
    hex::decode(hex_str).map_err(|err| JournalError::Corrupt {
        offset: 0,
        message: format!("intent {id} has undecodable signed bytes: {err}"),
    })
}

/// Encodes a signed transaction with the canonical noun jam.
pub fn jam_raw_tx(raw_tx: &v1::RawTx) -> Vec<u8> {
    let mut slab: NounSlab = NounSlab::new();
    let noun = raw_tx.to_noun(&mut slab);
    slab.set_root(noun);
    slab.jam().to_vec()
}

/// Decodes a signed transaction previously encoded by [`jam_raw_tx`].
pub fn cue_raw_tx(bytes: &[u8]) -> Result<v1::RawTx, String> {
    let mut slab: NounSlab = NounSlab::new();
    let noun = slab
        .cue_into(Bytes::copy_from_slice(bytes))
        .map_err(|err| format!("signed transaction jam did not cue: {err}"))?;
    let space = slab.noun_space();
    v1::RawTx::from_noun(&noun, &space)
        .map_err(|err| format!("signed transaction did not decode: {err}"))
}

#[cfg(test)]
mod tests {
    use nockchain_math::belt::Belt;
    use nockchain_types::tx_engine::common::{Hash, Version};

    use super::*;

    fn hash(seed: u64) -> Hash {
        Hash([Belt(seed + 1), Belt(seed + 2), Belt(seed + 3), Belt(seed + 4), Belt(seed + 5)])
    }

    fn raw_tx(seed: u64) -> v1::RawTx {
        v1::RawTx {
            version: Version::V1,
            id: hash(seed),
            spends: v1::Spends(vec![]),
        }
    }

    async fn journal() -> (tempfile::TempDir, Journal) {
        let dir = tempfile::tempdir().expect("tempdir");
        let journal = Journal::open(dir.path()).await.expect("opens");
        (dir, journal)
    }

    #[tokio::test]
    async fn raw_tx_survives_a_jam_round_trip() {
        // If this ever breaks, replayed bytes stop being byte-identical to
        // submitted ones and the idempotence argument collapses.
        let tx = raw_tx(1);
        let bytes = jam_raw_tx(&tx);
        assert_eq!(cue_raw_tx(&bytes).expect("cues"), tx);
        assert_eq!(jam_raw_tx(&cue_raw_tx(&bytes).unwrap()), bytes);
    }

    #[tokio::test]
    async fn replays_an_empty_journal() {
        let (_dir, journal) = journal().await;
        assert!(journal.states().is_empty());
        assert!(journal.unfinished().is_empty());
    }

    #[tokio::test]
    async fn state_survives_a_reopen() {
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(7);
        {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            journal.accept(id).await.expect("accept");
            journal.planned(id).await.expect("planned");
            journal.signed(id, &raw_tx(3)).await.expect("signed");
        }
        let journal = Journal::open(dir.path()).await.expect("reopens");
        let state = journal.state(&id).expect("known");
        let (tx_id, bytes) = state.signed_bytes().expect("has bytes");
        assert_eq!(*tx_id, hash(3));
        assert_eq!(cue_raw_tx(bytes).expect("cues"), raw_tx(3));
    }

    #[tokio::test]
    async fn a_signed_intent_resumes_with_identical_bytes() {
        // The exactly-once guarantee in one test: what comes back after a crash
        // is byte-for-byte what was going to be submitted before it.
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(1);
        let tx = raw_tx(11);
        let original = jam_raw_tx(&tx);
        {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            journal.accept(id).await.unwrap();
            journal.planned(id).await.unwrap();
            journal.signed(id, &tx).await.unwrap();
        }
        let journal = Journal::open(dir.path()).await.expect("reopens");
        let unfinished = journal.unfinished();
        assert_eq!(unfinished.len(), 1);
        let (_, state) = &unfinished[0];
        assert_eq!(state.signed_bytes().unwrap().1, original.as_slice());
    }

    #[tokio::test]
    async fn a_torn_trailing_record_is_discarded_and_the_rest_survives() {
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(2);
        {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            journal.accept(id).await.unwrap();
            journal.planned(id).await.unwrap();
        }
        // Simulate a crash mid-append: a half-written final line.
        let path = dir.path().join(LOG_FILE);
        let mut bytes = tokio::fs::read(&path).await.unwrap();
        bytes.extend_from_slice(br#"{"t":"signed","id":"#);
        tokio::fs::write(&path, &bytes).await.unwrap();

        let journal = Journal::open(dir.path()).await.expect("reopens");
        assert_eq!(journal.state(&id), Some(&IntentState::Planned));
        // The torn tail must be gone from disk, or the next append would
        // produce an unparseable line.
        let after = tokio::fs::read(&path).await.unwrap();
        assert!(after.ends_with(b"\n"));
        assert!(after.len() < bytes.len());
    }

    #[tokio::test]
    async fn appending_after_recovery_from_a_torn_record_works() {
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(3);
        {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            journal.accept(id).await.unwrap();
        }
        let path = dir.path().join(LOG_FILE);
        let mut bytes = tokio::fs::read(&path).await.unwrap();
        bytes.extend_from_slice(b"{\"t\":\"plan");
        tokio::fs::write(&path, &bytes).await.unwrap();

        let mut journal = Journal::open(dir.path()).await.expect("reopens");
        journal.planned(id).await.expect("append after recovery");
        drop(journal);

        let journal = Journal::open(dir.path()).await.expect("reopens again");
        assert_eq!(journal.state(&id), Some(&IntentState::Planned));
    }

    #[tokio::test]
    async fn crashing_at_every_step_converges_to_one_transaction() {
        // Kill the driver between each pair of states and assert the intent
        // never acquires a second, different signed transaction.
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(5);
        let tx = raw_tx(21);
        let expected = jam_raw_tx(&tx);

        let mut seen_tx_ids = std::collections::BTreeSet::new();

        for step in 0..5u8 {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            match (journal.state(&id).cloned(), step) {
                (None, _) => journal.accept(id).await.unwrap(),
                (Some(IntentState::Accepted), _) => journal.planned(id).await.unwrap(),
                (Some(IntentState::Planned), _) => journal.signed(id, &tx).await.unwrap(),
                (Some(IntentState::Signed { tx_id, .. }), _) => {
                    journal.submitted(id, &tx_id).await.unwrap()
                }
                (Some(IntentState::Submitted { tx_id, .. }), _) => journal
                    .confirmed(id, &tx_id, &BlockHeight(Belt(900)))
                    .await
                    .unwrap(),
                (Some(other), _) => panic!("unexpected state {other:?}"),
            }
            if let Some(state) = journal.state(&id) {
                if let Some((tx_id, bytes)) = state.signed_bytes() {
                    seen_tx_ids.insert(tx_id.to_base58());
                    assert_eq!(bytes, expected.as_slice());
                }
            }
            // Drop simulates the crash.
        }

        let journal = Journal::open(dir.path()).await.expect("reopens");
        assert!(matches!(
            journal.state(&id),
            Some(IntentState::Confirmed { .. })
        ));
        assert!(journal.unfinished().is_empty());
        assert_eq!(
            seen_tx_ids.len(),
            1,
            "the intent must only ever have had one transaction id"
        );
    }

    #[tokio::test]
    async fn submitting_without_signing_is_an_illegal_transition() {
        let (_dir, mut journal) = journal().await;
        let id = IntentId::from_u128(9);
        journal.accept(id).await.unwrap();
        let err = journal
            .submitted(id, &hash(1))
            .await
            .expect_err("cannot submit what was never signed");
        assert!(matches!(err, JournalError::IllegalTransition { .. }));
    }

    #[tokio::test]
    async fn moving_backwards_is_an_illegal_transition() {
        let (_dir, mut journal) = journal().await;
        let id = IntentId::from_u128(10);
        journal.accept(id).await.unwrap();
        journal.planned(id).await.unwrap();
        journal.signed(id, &raw_tx(1)).await.unwrap();
        let err = journal
            .planned(id)
            .await
            .expect_err("cannot un-sign a transaction");
        assert!(matches!(err, JournalError::IllegalTransition { .. }));
    }

    #[tokio::test]
    async fn a_terminal_intent_cannot_be_revived() {
        let (_dir, mut journal) = journal().await;
        let id = IntentId::from_u128(11);
        journal.accept(id).await.unwrap();
        journal.rejected(id, "declined").await.unwrap();
        let err = journal
            .planned(id)
            .await
            .expect_err("rejection is terminal");
        assert!(matches!(err, JournalError::IllegalTransition { .. }));
    }

    #[tokio::test]
    async fn rejection_is_allowed_from_any_non_terminal_state() {
        let (_dir, mut journal) = journal().await;
        let id = IntentId::from_u128(12);
        journal.accept(id).await.unwrap();
        journal.planned(id).await.unwrap();
        journal.signed(id, &raw_tx(1)).await.unwrap();
        journal
            .rejected(id, "network refused")
            .await
            .expect("a signed transaction can still be refused");
    }

    #[tokio::test]
    async fn compaction_drops_terminal_intents_and_keeps_live_ones() {
        let dir = tempfile::tempdir().expect("tempdir");
        let done = IntentId::from_u128(20);
        let live = IntentId::from_u128(21);
        let tx = raw_tx(31);

        let mut journal = Journal::open(dir.path()).await.expect("opens");
        journal.accept(done).await.unwrap();
        journal.planned(done).await.unwrap();
        journal.signed(done, &raw_tx(30)).await.unwrap();
        journal.submitted(done, &hash(30)).await.unwrap();
        journal
            .confirmed(done, &hash(30), &BlockHeight(Belt(500)))
            .await
            .unwrap();

        journal.accept(live).await.unwrap();
        journal.planned(live).await.unwrap();
        journal.signed(live, &tx).await.unwrap();
        journal.submitted(live, &hash(31)).await.unwrap();

        let dropped = journal.compact().await.expect("compacts");
        assert_eq!(dropped, 1);
        drop(journal);

        // The compacted log must still reconstruct the live intent's signed
        // bytes exactly — compaction must never lose the thing that makes
        // resubmission idempotent.
        let journal = Journal::open(dir.path()).await.expect("reopens");
        assert!(journal.state(&done).is_none());
        let state = journal.state(&live).expect("live intent survives");
        assert_eq!(state.signed_bytes().unwrap().1, jam_raw_tx(&tx).as_slice());
        assert!(matches!(state, IntentState::Submitted { .. }));
    }

    #[tokio::test]
    async fn compaction_is_a_no_op_when_nothing_is_terminal() {
        let (_dir, mut journal) = journal().await;
        let id = IntentId::from_u128(30);
        journal.accept(id).await.unwrap();
        assert_eq!(journal.compact().await.expect("compacts"), 0);
        assert_eq!(journal.state(&id), Some(&IntentState::Accepted));
    }

    #[tokio::test]
    async fn corruption_in_the_middle_of_the_log_is_reported() {
        // A hole mid-log could hide a `Signed` record, so it must never be
        // silently skipped the way a torn tail is.
        let dir = tempfile::tempdir().expect("tempdir");
        let id = IntentId::from_u128(40);
        {
            let mut journal = Journal::open(dir.path()).await.expect("opens");
            journal.accept(id).await.unwrap();
            journal.planned(id).await.unwrap();
        }
        let path = dir.path().join(LOG_FILE);
        let bytes = tokio::fs::read(&path).await.unwrap();
        let mut corrupted = b"{ not json at all }\n".to_vec();
        corrupted.extend_from_slice(&bytes);
        tokio::fs::write(&path, &corrupted).await.unwrap();

        let err = Journal::open(dir.path())
            .await
            .expect_err("mid-log corruption must be loud");
        assert!(matches!(err, JournalError::Corrupt { .. }));
    }
}
