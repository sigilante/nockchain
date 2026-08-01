//! Turning a balance snapshot into spendable candidates — without losing notes.
//!
//! The reconstructed driver's balance stage logged `"Skipping note with custom
//! lock conditions (not simple PKH)"` and dropped the note on the floor
//! and dropped the note on the floor. A caller could not tell an empty wallet
//! from a wallet full of timelocked notes, which rules out escrow designs and
//! makes "insufficient funds" unfalsifiable.
//!
//! This module keeps every note. Notes the driver can spend become
//! [`wallet_tx_builder::types::CandidateNote`]s; notes it cannot become
//! `(Name, `[`UnspendableReason`]`)` pairs on the same [`ClassifiedNotes`]. The
//! reason is typed and actionable — "supply this preimage", "wait until this
//! height", "you hold 1 of the 2 required keys" — which is the Rust equivalent
//! of the `missingUnlocks()` report the iris `SpendBuilder` exposes.

use std::collections::{BTreeMap, BTreeSet};

use nockchain_types::tx_engine::common::{BlockHeight, FirstName, Hash, Name};
use nockchain_types::tx_engine::v1;
use nockchain_types::tx_engine::v1::tx::{LockPrimitive, SpendCondition};
use wallet_tx_builder::lock_resolver::{
    LockMatcher, LockResolution, LockResolutionSource, ResolveLockRequest,
};
use wallet_tx_builder::note_data::DecodedNoteData;
use wallet_tx_builder::types::CandidateNote;

use crate::chain::{note_assets, BalanceSnapshot};

/// Why a note in the balance cannot be spent by this driver, right now.
///
/// Every variant names something the caller could act on, or a fact about the
/// chain that will change on its own. `Unknown*` variants are deliberately last
/// resorts — if one shows up often it means this module needs a new case, not
/// that the note is genuinely mysterious.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnspendableReason {
    /// The note is locked to a spend condition the intent never declared, so
    /// the driver has no way to know how to unlock it. Supply the condition in
    /// `TxIntent::from`.
    LockNotDeclared { first_name: Hash },
    /// A `%hax` primitive requires a preimage the driver does not hold.
    MissingPreimage { hash: Hash },
    /// An absolute timelock has not yet elapsed.
    AbsoluteTimelockNotMet {
        available_at: BlockHeight,
        current: BlockHeight,
    },
    /// A relative timelock measured from the note's origin page has not elapsed.
    RelativeTimelockNotMet {
        available_at: BlockHeight,
        current: BlockHeight,
    },
    /// An absolute or relative timelock has *expired*: the note's spend window
    /// has closed and it can never be spent under this condition again.
    TimelockWindowClosed { closed_at: BlockHeight },
    /// The condition needs `needed` signatures from a key set, and the signer
    /// only holds `have` of them.
    ThresholdUnmet { needed: u64, have: u64 },
    /// The note is locked with a `%brn` burn primitive and is unspendable by
    /// anyone, forever.
    Burned,
    /// The note's data could not be decoded well enough to classify it.
    Undecodable { message: String },
    /// A v0 note. Spendable only through the v0 migration sweep, which is a
    /// different code path than an ordinary payment.
    LegacyV0Note,
}

impl std::fmt::Display for UnspendableReason {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::LockNotDeclared { first_name } => write!(
                f,
                "locked to an undeclared spend condition (first-name {})",
                first_name.to_base58()
            ),
            Self::MissingPreimage { hash } => {
                write!(f, "needs the preimage of {}", hash.to_base58())
            }
            Self::AbsoluteTimelockNotMet {
                available_at,
                current,
            } => write!(
                f,
                "absolute timelock: spendable at block {}, chain is at {}",
                available_at.0 .0, current.0 .0
            ),
            Self::RelativeTimelockNotMet {
                available_at,
                current,
            } => write!(
                f,
                "relative timelock: spendable at block {}, chain is at {}",
                available_at.0 .0, current.0 .0
            ),
            Self::TimelockWindowClosed { closed_at } => {
                write!(f, "timelock window closed at block {}", closed_at.0 .0)
            }
            Self::ThresholdUnmet { needed, have } => {
                write!(f, "needs {needed} signature(s), signer holds {have}")
            }
            Self::Burned => f.write_str("burned; unspendable by anyone"),
            Self::Undecodable { message } => write!(f, "note data did not decode: {message}"),
            Self::LegacyV0Note => {
                f.write_str("v0 note; spendable only via the v0 migration sweep")
            }
        }
    }
}

impl UnspendableReason {
    /// Whether waiting could make this note spendable.
    ///
    /// Used to decide whether an intent that is short of funds should be
    /// rejected as terminally underfunded or retried later.
    pub fn resolves_with_time(&self) -> bool {
        matches!(
            self,
            Self::AbsoluteTimelockNotMet { .. } | Self::RelativeTimelockNotMet { .. }
        )
    }

    /// Whether supplying more information to the driver — a preimage, another
    /// spend condition, another signing key — could make this note spendable.
    pub fn resolves_with_more_context(&self) -> bool {
        matches!(
            self,
            Self::LockNotDeclared { .. }
                | Self::MissingPreimage { .. }
                | Self::ThresholdUnmet { .. }
        )
    }
}

/// A balance snapshot split into what can be spent and what cannot.
#[derive(Debug, Default)]
pub struct ClassifiedNotes {
    /// Notes the driver can build a spend for.
    pub spendable: Vec<CandidateNote>,
    /// Every other note in the snapshot, with the reason it was excluded.
    /// Never silently dropped.
    pub unspendable: Vec<(Name, UnspendableReason)>,
}

impl ClassifiedNotes {
    /// Total value of spendable notes.
    pub fn spendable_total(&self) -> u64 {
        self.spendable
            .iter()
            .map(|c| c.assets().0 as u64)
            .fold(0u64, |acc, v| acc.saturating_add(v))
    }

    /// Value that is present in the wallet but currently locked away, grouped
    /// by whether it will free up on its own.
    pub fn blocked_total(&self, snapshot: &BalanceSnapshot) -> BlockedFunds {
        let by_name: BTreeMap<[u64; 10], &v1::Note> = snapshot
            .notes
            .iter()
            .map(|(name, note)| (name_key(name), note))
            .collect();
        let mut blocked = BlockedFunds::default();
        for (name, reason) in &self.unspendable {
            let Some(note) = by_name.get(&name_key(name)) else {
                continue;
            };
            let assets = note_assets(note);
            if reason.resolves_with_time() {
                blocked.pending_timelock = blocked.pending_timelock.saturating_add(assets);
            } else if reason.resolves_with_more_context() {
                blocked.needs_context = blocked.needs_context.saturating_add(assets);
            } else {
                blocked.permanently_locked = blocked.permanently_locked.saturating_add(assets);
            }
        }
        blocked
    }
}

/// Value in the wallet that this intent could not reach, by remedy.
#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct BlockedFunds {
    /// Will become spendable by itself once the chain advances.
    pub pending_timelock: u64,
    /// Would become spendable if the caller supplied a preimage, key, or lock.
    pub needs_context: u64,
    /// Burned, expired, or otherwise gone.
    pub permanently_locked: u64,
}

// A `Name` is two 5-limb hashes; flattening to a fixed array gives a cheap
// `Ord`/`Hash` key without cloning the hashes themselves.
fn name_key(name: &Name) -> [u64; 10] {
    let first = name.first.to_array();
    let last = name.last.to_array();
    [
        first[0], first[1], first[2], first[3], first[4], last[0], last[1], last[2], last[3],
        last[4],
    ]
}

/// The unlock context the driver holds: which keys it can sign with, which
/// preimages it knows, and which spend conditions it was told about.
///
/// This is the driver-side counterpart to a wallet's key store. It never holds
/// a private key — only the *hashes* of keys the signer claims to control,
/// which is all that lock satisfaction needs to be decided.
#[derive(Debug, Default, Clone)]
pub struct UnlockContext {
    signer_pkhs: BTreeSet<[u64; 5]>,
    preimages: BTreeMap<[u64; 5], Vec<u8>>,
    coinbase_relative_min: Option<u64>,
}

impl UnlockContext {
    pub fn new() -> Self {
        Self::default()
    }

    /// Declares a public-key hash the signer can produce a signature for.
    pub fn with_signer_pkh(mut self, pkh: Hash) -> Self {
        self.signer_pkhs.insert(pkh.to_array());
        self
    }

    pub fn with_signer_pkhs<I: IntoIterator<Item = Hash>>(mut self, pkhs: I) -> Self {
        for pkh in pkhs {
            self.signer_pkhs.insert(pkh.to_array());
        }
        self
    }

    /// Registers a `%hax` preimage, keyed by its hash.
    pub fn with_preimage(mut self, hash: Hash, preimage: Vec<u8>) -> Self {
        self.preimages.insert(hash.to_array(), preimage);
        self
    }

    /// Sets the relative timelock, in blocks, that marks a lock as
    /// coinbase-style. Needed to reconstruct coinbase PKH locks.
    pub fn with_coinbase_relative_min(mut self, blocks: u64) -> Self {
        self.coinbase_relative_min = Some(blocks);
        self
    }

    pub fn holds_key(&self, pkh: &Hash) -> bool {
        self.signer_pkhs.contains(&pkh.to_array())
    }

    pub fn holds_preimage(&self, hash: &Hash) -> bool {
        self.preimages.contains_key(&hash.to_array())
    }

    pub fn preimage(&self, hash: &Hash) -> Option<&[u8]> {
        self.preimages.get(&hash.to_array()).map(|v| v.as_slice())
    }

    pub fn coinbase_relative_min(&self) -> Option<u64> {
        self.coinbase_relative_min
    }

    /// A representative signer hash, for planner APIs that take a single one.
    pub fn primary_signer_pkh(&self) -> Option<Hash> {
        self.signer_pkhs.iter().next().map(|limbs| {
            Hash([
                nockchain_math::belt::Belt(limbs[0]),
                nockchain_math::belt::Belt(limbs[1]),
                nockchain_math::belt::Belt(limbs[2]),
                nockchain_math::belt::Belt(limbs[3]),
                nockchain_math::belt::Belt(limbs[4]),
            ])
        })
    }
}

/// Decides, for a single spend condition, whether the held context satisfies it.
///
/// Returns `Ok(())` when the condition can be met at `height` for a note that
/// originated at `origin_page`, and the first blocking [`UnspendableReason`]
/// otherwise. Primitives are checked in declaration order so the reported
/// reason is the one a user would hit first.
pub fn check_spend_condition(
    condition: &SpendCondition,
    context: &UnlockContext,
    height: &BlockHeight,
    origin_page: &BlockHeight,
) -> std::result::Result<(), UnspendableReason> {
    for primitive in condition.iter() {
        match primitive {
            LockPrimitive::Burn => return Err(UnspendableReason::Burned),
            LockPrimitive::Pkh(pkh) => {
                let have = pkh
                    .hashes
                    .iter()
                    .filter(|hash| context.holds_key(hash))
                    .count() as u64;
                if have < pkh.m {
                    return Err(UnspendableReason::ThresholdUnmet { needed: pkh.m, have });
                }
            }
            LockPrimitive::Hax(hax) => {
                // A `%hax` set requires *every* preimage, not one of them.
                for hash in hax.0.iter() {
                    if !context.holds_preimage(hash) {
                        return Err(UnspendableReason::MissingPreimage { hash: hash.clone() });
                    }
                }
            }
            LockPrimitive::Tim(tim) => {
                let now = height.0 .0;

                if let Some(min) = &tim.abs.min {
                    if now < min.0 .0 {
                        return Err(UnspendableReason::AbsoluteTimelockNotMet {
                            available_at: min.clone(),
                            current: height.clone(),
                        });
                    }
                }
                if let Some(max) = &tim.abs.max {
                    if now > max.0 .0 {
                        return Err(UnspendableReason::TimelockWindowClosed {
                            closed_at: max.clone(),
                        });
                    }
                }

                let origin = origin_page.0 .0;
                if let Some(min) = &tim.rel.min {
                    let available = origin.saturating_add(min.0 .0);
                    if now < available {
                        return Err(UnspendableReason::RelativeTimelockNotMet {
                            available_at: BlockHeight(nockchain_math::belt::Belt(available)),
                            current: height.clone(),
                        });
                    }
                }
                if let Some(max) = &tim.rel.max {
                    let closed = origin.saturating_add(max.0 .0);
                    if now > closed {
                        return Err(UnspendableReason::TimelockWindowClosed {
                            closed_at: BlockHeight(nockchain_math::belt::Belt(closed)),
                        });
                    }
                }
            }
        }
    }
    Ok(())
}

/// A [`LockMatcher`] backed by an explicit set of declared spend conditions.
///
/// Generalises `LockRootLockMatcher`, which matches exactly one lock root, to
/// the set of conditions an intent declares in `TxIntent::from`. A note matches
/// when its first-name equals the first-name derived from one of those
/// conditions — the same `SpendCondition -> Lock -> lock-root -> FirstName`
/// derivation the wallet uses, so a driver-derived first-name and a
/// wallet-derived one agree by construction.
#[derive(Debug, Clone, Default)]
pub struct SpendConditionMatcher {
    /// first-name limbs -> the condition that produces them.
    by_first_name: BTreeMap<[u64; 5], SpendCondition>,
}

impl SpendConditionMatcher {
    /// Builds a matcher from declared spend conditions.
    ///
    /// A condition whose lock-root cannot be hashed is skipped and reported, so
    /// a malformed entry in one intent cannot silently disable matching for the
    /// others.
    pub fn new<I: IntoIterator<Item = SpendCondition>>(
        conditions: I,
    ) -> (Self, Vec<(SpendCondition, String)>) {
        let mut by_first_name = BTreeMap::new();
        let mut rejected = Vec::new();
        for condition in conditions {
            match condition.first_name() {
                Ok(first_name) => {
                    by_first_name.insert(first_name.as_hash().to_array(), condition);
                }
                Err(err) => rejected.push((condition, err.to_string())),
            }
        }
        (Self { by_first_name }, rejected)
    }

    /// The condition that produces `first_name`, if declared.
    pub fn condition_for(&self, first_name: &Hash) -> Option<&SpendCondition> {
        self.by_first_name.get(&first_name.to_array())
    }

    /// Every first-name this matcher accepts. These are exactly the names to
    /// query the node's balance endpoint with.
    pub fn first_names(&self) -> Vec<FirstName> {
        self.by_first_name
            .keys()
            .map(|limbs| {
                FirstName(Hash([
                    nockchain_math::belt::Belt(limbs[0]),
                    nockchain_math::belt::Belt(limbs[1]),
                    nockchain_math::belt::Belt(limbs[2]),
                    nockchain_math::belt::Belt(limbs[3]),
                    nockchain_math::belt::Belt(limbs[4]),
                ]))
            })
            .collect()
    }

    pub fn is_empty(&self) -> bool {
        self.by_first_name.is_empty()
    }
}

impl LockMatcher for SpendConditionMatcher {
    fn matches(&self, note_first_name: &Hash, _spend_condition: &SpendCondition) -> bool {
        self.by_first_name.contains_key(&note_first_name.to_array())
    }

    fn select_v1_candidate(&self, request: ResolveLockRequest<'_>) -> LockResolution {
        match self.condition_for(request.note_first_name) {
            Some(condition) => LockResolution {
                source: LockResolutionSource::LockRootFirstName,
                spend_condition: Some(condition.clone()),
                spend_condition_count: None,
            },
            None => LockResolution::unknown(),
        }
    }
}

/// Splits a balance snapshot into spendable candidates and typed exclusions.
///
/// `origin_page` for relative timelocks comes from the note itself, so a note
/// that is merely young is reported as `RelativeTimelockNotMet` with the exact
/// height at which it frees up.
pub fn classify(
    snapshot: &BalanceSnapshot,
    matcher: &SpendConditionMatcher,
    context: &UnlockContext,
) -> ClassifiedNotes {
    let mut out = ClassifiedNotes::default();

    for (name, note) in &snapshot.notes {
        let candidate = CandidateNote::from_note(name, note);

        let (first_name, origin_page) = match note {
            v1::Note::V0(_) => {
                out.unspendable
                    .push((name.clone(), UnspendableReason::LegacyV0Note));
                continue;
            }
            v1::Note::V1(n) => (n.name.first.clone(), n.origin_page.clone()),
        };

        let Some(condition) = matcher.condition_for(&first_name) else {
            out.unspendable.push((
                name.clone(),
                UnspendableReason::LockNotDeclared { first_name },
            ));
            continue;
        };

        match check_spend_condition(condition, context, &snapshot.height, &origin_page) {
            Ok(()) => out.spendable.push(candidate),
            Err(reason) => out.unspendable.push((name.clone(), reason)),
        }
    }

    out
}

/// Builds the `ResolveLockRequest` the planner's matcher expects.
///
/// Exposed so callers that drive the planner directly can reuse the driver's
/// lock policy instead of reimplementing it.
pub fn resolve_request<'a>(
    note_first_name: &'a Hash,
    decoded_note_data: &'a DecodedNoteData,
    signer_pkh: Option<&'a Hash>,
    context: &UnlockContext,
) -> ResolveLockRequest<'a> {
    ResolveLockRequest {
        note_first_name,
        decoded_note_data,
        signer_pkh,
        coinbase_relative_min: context.coinbase_relative_min(),
    }
}

#[cfg(test)]
mod tests {
    use nockchain_math::belt::Belt;
    use nockchain_types::tx_engine::common::{
        BlockHeightDelta, Nicks, TimelockRangeAbsolute, TimelockRangeRelative, Version,
    };
    use nockchain_types::tx_engine::v1::note::{NoteData, NoteV1};
    use nockchain_types::tx_engine::v1::tx::{Hax, LockTim, Pkh};

    use super::*;

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

    /// Builds a note locked to `condition`, so that its first-name is the one
    /// the matcher will derive from that same condition.
    fn note_for(condition: &SpendCondition, origin_page: u64, assets: u64) -> (Name, v1::Note) {
        let first = condition.first_name().expect("first-name derives").into_hash();
        let name = Name::new(first, hash(999));
        let note = v1::Note::V1(NoteV1 {
            version: Version::V1,
            origin_page: height(origin_page),
            name: name.clone(),
            note_data: NoteData(vec![]),
            assets: Nicks(assets as usize),
        });
        (name, note)
    }

    fn snapshot(at: u64, notes: Vec<(Name, v1::Note)>) -> BalanceSnapshot {
        BalanceSnapshot {
            height: height(at),
            block_id: hash(7),
            notes,
        }
    }

    fn tim(rel_min: Option<u64>, abs_min: Option<u64>, abs_max: Option<u64>) -> LockPrimitive {
        LockPrimitive::Tim(LockTim {
            rel: TimelockRangeRelative::new(rel_min.map(|v| BlockHeightDelta(Belt(v))), None),
            abs: TimelockRangeAbsolute {
                min: abs_min.map(height),
                max: abs_max.map(height),
            },
        })
    }

    #[test]
    fn simple_pkh_note_is_spendable_when_the_key_is_held() {
        let key = hash(1);
        let condition = SpendCondition::simple_pkh(key.clone());
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, rejected) = SpendConditionMatcher::new([condition]);
        assert!(rejected.is_empty());
        let context = UnlockContext::new().with_signer_pkh(key);

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(classified.spendable.len(), 1);
        assert!(classified.unspendable.is_empty());
        assert_eq!(classified.spendable_total(), 500);
    }

    #[test]
    fn undeclared_lock_is_reported_not_dropped() {
        // The whole point of this module: a note the driver cannot spend still
        // shows up, with a reason.
        let declared = SpendCondition::simple_pkh(hash(1));
        let other = SpendCondition::simple_pkh(hash(2));
        let (name, note) = note_for(&other, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([declared]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert!(classified.spendable.is_empty());
        assert_eq!(classified.unspendable.len(), 1);
        assert!(matches!(
            classified.unspendable[0].1,
            UnspendableReason::LockNotDeclared { .. }
        ));
    }

    #[test]
    fn hashlocked_note_reports_the_missing_preimage() {
        let secret = hash(42);
        let condition = SpendCondition::new(vec![
            LockPrimitive::Pkh(Pkh::new(1, vec![hash(1)])),
            LockPrimitive::Hax(Hax::new(vec![secret.clone()])),
        ]);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(
            classified.unspendable[0].1,
            UnspendableReason::MissingPreimage {
                hash: secret.clone()
            }
        );
        assert!(classified.unspendable[0].1.resolves_with_more_context());
    }

    #[test]
    fn supplying_the_preimage_makes_a_hashlocked_note_spendable() {
        let secret = hash(42);
        let condition = SpendCondition::new(vec![
            LockPrimitive::Pkh(Pkh::new(1, vec![hash(1)])),
            LockPrimitive::Hax(Hax::new(vec![secret.clone()])),
        ]);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new()
            .with_signer_pkh(hash(1))
            .with_preimage(secret, b"open sesame".to_vec());

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(classified.spendable.len(), 1);
        assert!(classified.unspendable.is_empty());
    }

    #[test]
    fn relative_timelock_reports_the_height_it_frees_up_at() {
        let condition = SpendCondition::coinbase_pkh(hash(1), 100);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(50, vec![(name, note)]), &matcher, &context);

        // origin_page 10 + relative min 100 = spendable at 110.
        assert_eq!(
            classified.unspendable[0].1,
            UnspendableReason::RelativeTimelockNotMet {
                available_at: height(110),
                current: height(50),
            }
        );
        assert!(classified.unspendable[0].1.resolves_with_time());
    }

    #[test]
    fn relative_timelock_clears_once_the_chain_advances() {
        let condition = SpendCondition::coinbase_pkh(hash(1), 100);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(110, vec![(name, note)]), &matcher, &context);

        assert_eq!(classified.spendable.len(), 1);
    }

    #[test]
    fn absolute_timelock_and_expiry_are_distinguished() {
        let not_yet = SpendCondition::new(vec![
            LockPrimitive::Pkh(Pkh::new(1, vec![hash(1)])),
            tim(None, Some(200), None),
        ]);
        let expired = SpendCondition::new(vec![
            LockPrimitive::Pkh(Pkh::new(1, vec![hash(1)])),
            tim(None, None, Some(50)),
        ]);
        let (name_a, note_a) = note_for(&not_yet, 10, 100);
        let (name_b, note_b) = note_for(&expired, 10, 100);
        let (matcher, _) = SpendConditionMatcher::new([not_yet, expired]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(
            &snapshot(100, vec![(name_a, note_a), (name_b, note_b)]),
            &matcher,
            &context,
        );

        let reasons: Vec<_> = classified.unspendable.iter().map(|(_, r)| r).collect();
        assert!(reasons
            .iter()
            .any(|r| matches!(r, UnspendableReason::AbsoluteTimelockNotMet { .. })));
        assert!(reasons
            .iter()
            .any(|r| matches!(r, UnspendableReason::TimelockWindowClosed { .. })));
        // An expired window is not something waiting will fix.
        let closed = reasons
            .iter()
            .find(|r| matches!(r, UnspendableReason::TimelockWindowClosed { .. }))
            .expect("expired note classified");
        assert!(!closed.resolves_with_time());
        assert!(!closed.resolves_with_more_context());
    }

    #[test]
    fn multisig_shortfall_reports_the_exact_threshold() {
        let condition = SpendCondition::new(vec![LockPrimitive::Pkh(Pkh::new(
            2,
            vec![hash(1), hash(2), hash(3)],
        ))]);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(
            classified.unspendable[0].1,
            UnspendableReason::ThresholdUnmet { needed: 2, have: 1 }
        );
    }

    #[test]
    fn multisig_is_spendable_once_the_threshold_is_met() {
        let condition = SpendCondition::new(vec![LockPrimitive::Pkh(Pkh::new(
            2,
            vec![hash(1), hash(2), hash(3)],
        ))]);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkhs([hash(1), hash(3)]);

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(classified.spendable.len(), 1);
    }

    #[test]
    fn burned_notes_are_permanently_locked() {
        let condition = SpendCondition::new(vec![LockPrimitive::Burn]);
        let (name, note) = note_for(&condition, 10, 500);
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot(100, vec![(name, note)]), &matcher, &context);

        assert_eq!(classified.unspendable[0].1, UnspendableReason::Burned);
        assert!(!classified.unspendable[0].1.resolves_with_time());
        assert!(!classified.unspendable[0].1.resolves_with_more_context());
    }

    #[test]
    fn every_note_in_the_snapshot_is_accounted_for() {
        // The regression guard for the defect this module exists to fix: no
        // note may vanish between the balance snapshot and the classification.
        let mine = SpendCondition::simple_pkh(hash(1));
        let theirs = SpendCondition::simple_pkh(hash(2));
        let timelocked = SpendCondition::coinbase_pkh(hash(1), 100);
        let burned = SpendCondition::new(vec![LockPrimitive::Burn]);

        let notes = vec![
            note_for(&mine, 1, 100),
            note_for(&theirs, 1, 200),
            note_for(&timelocked, 1, 400),
            note_for(&burned, 1, 800),
        ];
        let snapshot = snapshot(50, notes);
        let (matcher, _) =
            SpendConditionMatcher::new([mine, theirs.clone(), timelocked, burned]);
        let context = UnlockContext::new().with_signer_pkh(hash(1));

        let classified = classify(&snapshot, &matcher, &context);

        assert_eq!(
            classified.spendable.len() + classified.unspendable.len(),
            snapshot.notes.len(),
            "a note disappeared during classification"
        );

        let blocked = classified.blocked_total(&snapshot);
        assert_eq!(blocked.pending_timelock, 400);
        // `theirs` is declared but its key is not held, so it is a threshold
        // shortfall rather than an undeclared lock.
        assert_eq!(blocked.needs_context, 200);
        assert_eq!(blocked.permanently_locked, 800);
        assert_eq!(classified.spendable_total(), 100);
    }

    #[test]
    fn matcher_first_names_match_the_wallet_derivation() {
        // `SpendConditionMatcher` must derive first-names exactly as
        // `SpendCondition::first_name` does, or the driver queries the node for
        // a name no note carries and silently sees a zero balance.
        let condition = SpendCondition::simple_pkh(hash(1));
        let expected = condition.first_name().expect("derives");
        let (matcher, _) = SpendConditionMatcher::new([condition]);
        assert_eq!(matcher.first_names(), vec![expected]);
    }
}

