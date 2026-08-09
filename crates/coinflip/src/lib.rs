//! A two-party commit–reveal coinflip settled on Nockchain.
//!
//! # What this demonstrates
//!
//! That Nockchain's lock primitives — `Hax` (hashlock), `Pkh` (m-of-n), `Tim`
//! (timelock) — compose into a real interactive protocol, and that `tx-driver`
//! can fund and settle it.
//!
//! # The protocol
//!
//! ```text
//!   1. Alice picks secret a, publishes commitment h(a).
//!   2. Bob picks secret b, publishes h(b).          <- after seeing h(a), not a
//!   3. Both fund the stake note, locked as below.
//!   4. Alice reveals a.
//!   5. Bob reveals b.
//!   outcome = parity(a XOR b):  even -> Alice, odd -> Bob
//! ```
//!
//! Step 2 is what makes it fair. Bob commits before seeing Alice's *secret*, so
//! he cannot pick `b` to steer the result; and once committed, neither party can
//! produce a different preimage for their published hash. Each player holds
//! exactly one secret, so there is no last-mover choice to exploit.
//!
//! An earlier draft of this had each player commit to *two* secrets — one per
//! outcome — with a four-branch lock selecting the winner. That construction is
//! broken: whoever reveals second sees the opponent's secret and then picks
//! whichever of their own two secrets wins. One secret per player is what closes
//! it.
//!
//! # The lock
//!
//! ```text
//!   Lock::V2
//!     branch 0 (settle): Hax{h(a), h(b)}  AND  Pkh{m=2, {alice, bob}}
//!     branch 1 (refund): Tim{abs.min = deadline}  AND  Pkh{m=2, {alice, bob}}
//! ```
//!
//! Branch 0 is spendable only once *both* secrets are public — `hax` requires
//! every preimage in its set, not any one of them — and only with both
//! signatures. Branch 1 lets the stake be returned after the deadline if the
//! game never completes.
//!
//! # What this does and does not guarantee
//!
//! **Guaranteed:** the *outcome* is unbiased and cryptographically binding.
//! Neither player can influence it after committing, and neither can equivocate.
//!
//! **Not guaranteed:** that the loser pays. Settlement is cooperative — branch 0
//! needs both signatures. A losing player can refuse to sign, and the stake then
//! returns to both parties via branch 1 at the deadline. So cheating is
//! *griefable but not profitable*: the cheat denies the winner their winnings, it
//! does not transfer them to the cheat.
//!
//! Making the loser pay needs something these primitives do not have. Locks here
//! are predicates on *whether* a note may be spent, never covenants on *where*
//! its value goes, and no lock can compute `parity(a XOR b)`. The standard fix is
//! per-player bonds in separate notes, forfeitable on non-cooperation. That is a
//! natural extension of this crate and is not implemented.

// Tests use `unwrap`; a panic there is the failure signal.
#![cfg_attr(test, allow(clippy::unwrap_used))]

use nockchain_math::belt::Belt;
use nockchain_types::tx_engine::common::{
    BlockHeight, FirstName, Hash, TimelockRangeAbsolute, TimelockRangeRelative,
};
use nockchain_types::tx_engine::v1::hashable::{hash_leaf_belt, hash_pair};
use nockchain_types::tx_engine::v1::tx::{
    Hax, Lock, LockPrimitive, LockTim, LockV2, Pkh, SpendCondition,
};

/// Errors that can arise building or reading a game.
#[derive(Debug, thiserror::Error)]
pub enum CoinflipError {
    #[error("both players committed to the same secret hash; refusing to build a degenerate lock")]
    DuplicateCommitment,
    #[error("players must have distinct public-key hashes")]
    DuplicatePlayer,
    #[error("stake must be greater than zero")]
    ZeroStake,
    #[error("failed to hash the game lock: {0}")]
    LockHash(String),
}

/// A player's private secret: four field elements, ~256 bits of entropy.
///
/// Represented as the Hoon noun `[w x y z]`, i.e. `[w [x [y z]]]`, so its
/// commitment is `hash-noun` of that tree — the same digest the `hax` primitive
/// recomputes from the revealed preimage on chain.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Secret([Belt; 4]);

impl Secret {
    /// Builds a secret from four field elements.
    pub fn new(limbs: [u64; 4]) -> Self {
        Self([Belt(limbs[0]), Belt(limbs[1]), Belt(limbs[2]), Belt(limbs[3])])
    }

    /// The commitment published in the commit phase.
    ///
    /// Mirrors Hoon's `+hash-noun`: cells hash as pairs of their children's
    /// digests, atoms hash as `%leaf`. For `[w x y z]` that is
    /// `pair(w, pair(x, pair(y, z)))`.
    pub fn commitment(&self) -> Hash {
        let [w, x, y, z] = self.0;
        hash_pair(
            &hash_leaf_belt(w),
            &hash_pair(
                &hash_leaf_belt(x),
                &hash_pair(&hash_leaf_belt(y), &hash_leaf_belt(z)),
            ),
        )
    }

    /// The parity contributed to the outcome.
    ///
    /// Folds all four limbs so the whole secret matters; using only the first
    /// would let a player grind the rest for free.
    fn parity(&self) -> u64 {
        self.0.iter().fold(0u64, |acc, limb| acc ^ limb.0) & 1
    }

    /// The raw limbs, for handing the preimage to a witness.
    pub fn limbs(&self) -> [u64; 4] {
        [self.0[0].0, self.0[1].0, self.0[2].0, self.0[3].0]
    }
}

/// Which player wins.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Winner {
    Alice,
    Bob,
}

/// A player as seen by the other side during the commit phase.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PlayerCommitment {
    /// The public-key hash that will sign settlement.
    pub pkh: Hash,
    /// `h(secret)`, published before the opponent reveals.
    pub commitment: Hash,
}

/// Everything both players agree on before any money moves.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GameTerms {
    pub alice: PlayerCommitment,
    pub bob: PlayerCommitment,
    /// Each player's stake, in nicks. The pot is twice this.
    pub stake_nicks: u64,
    /// Block height at or after which the refund branch opens.
    pub refund_after: BlockHeight,
}

impl GameTerms {
    /// Validates the terms and returns them.
    pub fn new(
        alice: PlayerCommitment,
        bob: PlayerCommitment,
        stake_nicks: u64,
        refund_after: BlockHeight,
    ) -> Result<Self, CoinflipError> {
        if stake_nicks == 0 {
            return Err(CoinflipError::ZeroStake);
        }
        if alice.pkh == bob.pkh {
            return Err(CoinflipError::DuplicatePlayer);
        }
        // A shared commitment would collapse the `hax` z-set to a single
        // element, so one revealed preimage would unlock the pot.
        if alice.commitment == bob.commitment {
            return Err(CoinflipError::DuplicateCommitment);
        }
        Ok(Self {
            alice,
            bob,
            stake_nicks,
            refund_after,
        })
    }

    /// The pot: both stakes.
    pub fn pot_nicks(&self) -> u64 {
        self.stake_nicks.saturating_mul(2)
    }

    /// Branch 0: spendable once both secrets are public and both players sign.
    pub fn settle_branch(&self) -> SpendCondition {
        SpendCondition::new(vec![
            LockPrimitive::Hax(Hax::new(vec![
                self.alice.commitment.clone(),
                self.bob.commitment.clone(),
            ])),
            LockPrimitive::Pkh(Pkh::new(
                2,
                vec![self.alice.pkh.clone(), self.bob.pkh.clone()],
            )),
        ])
    }

    /// Branch 1: spendable after the deadline, by both players together.
    pub fn refund_branch(&self) -> SpendCondition {
        SpendCondition::new(vec![
            LockPrimitive::Tim(LockTim {
                rel: TimelockRangeRelative::new(None, None),
                abs: TimelockRangeAbsolute {
                    min: Some(self.refund_after.clone()),
                    max: None,
                },
            }),
            LockPrimitive::Pkh(Pkh::new(
                2,
                vec![self.alice.pkh.clone(), self.bob.pkh.clone()],
            )),
        ])
    }

    /// The two-branch lock the stake note is committed to.
    pub fn lock(&self) -> Lock {
        Lock::V2(LockV2 {
            p: self.settle_branch(),
            q: self.refund_branch(),
        })
    }

    /// The consensus lock root. This is what an output commits to.
    pub fn lock_root(&self) -> Result<Hash, CoinflipError> {
        self.lock()
            .hash()
            .map_err(|err| CoinflipError::LockHash(err.to_string()))
    }

    /// The first-name the stake note will carry, and therefore the name to
    /// query a balance under.
    pub fn first_name(&self) -> Result<FirstName, CoinflipError> {
        let root = self.lock_root()?;
        FirstName::from_lock_root(&root).map_err(|err| CoinflipError::LockHash(err.to_string()))
    }

    /// The winner implied by a pair of revealed secrets.
    ///
    /// Checks each secret against its commitment first: a revealed value that
    /// does not match what was committed is not a valid reveal, and treating it
    /// as one would let a player equivocate.
    pub fn resolve(&self, alice: &Secret, bob: &Secret) -> Result<Winner, RevealError> {
        if alice.commitment() != self.alice.commitment {
            return Err(RevealError::CommitmentMismatch { player: "alice" });
        }
        if bob.commitment() != self.bob.commitment {
            return Err(RevealError::CommitmentMismatch { player: "bob" });
        }
        Ok(if alice.parity() ^ bob.parity() == 0 {
            Winner::Alice
        } else {
            Winner::Bob
        })
    }

    /// The public-key hash that should receive the pot.
    pub fn payee(&self, winner: Winner) -> &Hash {
        match winner {
            Winner::Alice => &self.alice.pkh,
            Winner::Bob => &self.bob.pkh,
        }
    }
}

/// Why a reveal was rejected.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RevealError {
    #[error("{player} revealed a secret that does not match their commitment")]
    CommitmentMismatch { player: &'static str },
}

/// A player's full private state.
#[derive(Debug, Clone)]
pub struct Player {
    pub pkh: Hash,
    pub secret: Secret,
}

impl Player {
    pub fn new(pkh: Hash, secret: Secret) -> Self {
        Self { pkh, secret }
    }

    /// What this player publishes in the commit phase.
    pub fn commit(&self) -> PlayerCommitment {
        PlayerCommitment {
            pkh: self.pkh.clone(),
            commitment: self.secret.commitment(),
        }
    }
}

#[cfg(test)]
mod tests {
    use tx_driver::notes::{check_spend_condition, UnlockContext, UnspendableReason};

    use super::*;

    fn hash(seed: u64) -> Hash {
        Hash([Belt(seed + 1), Belt(seed + 2), Belt(seed + 3), Belt(seed + 4), Belt(seed + 5)])
    }

    fn height(n: u64) -> BlockHeight {
        BlockHeight(Belt(n))
    }

    /// Alice's parity is even, Bob's is even -> XOR 0 -> Alice wins.
    fn alice_even() -> Secret {
        Secret::new([2, 4, 6, 8])
    }
    /// Odd parity.
    fn bob_odd() -> Secret {
        Secret::new([1, 2, 4, 8])
    }
    fn bob_even() -> Secret {
        Secret::new([2, 2, 4, 8])
    }

    fn game(alice: &Player, bob: &Player) -> GameTerms {
        GameTerms::new(alice.commit(), bob.commit(), 1_000_000, height(500)).expect("valid terms")
    }

    fn players() -> (Player, Player) {
        (
            Player::new(hash(1), alice_even()),
            Player::new(hash(2), bob_odd()),
        )
    }

    #[test]
    fn a_commitment_is_deterministic_and_secret_specific() {
        let a = Secret::new([1, 2, 3, 4]);
        assert_eq!(a.commitment(), a.commitment());
        assert_ne!(a.commitment(), Secret::new([1, 2, 3, 5]).commitment());
        // Order matters: the noun is a tree, not a set.
        assert_ne!(a.commitment(), Secret::new([4, 3, 2, 1]).commitment());
    }

    #[test]
    fn the_outcome_is_the_xor_of_both_parities() {
        let alice_e = Player::new(hash(1), alice_even());
        let bob_o = Player::new(hash(2), bob_odd());
        let bob_e = Player::new(hash(2), bob_even());

        // even ^ odd = 1 -> Bob
        let g = game(&alice_e, &bob_o);
        assert_eq!(
            g.resolve(&alice_e.secret, &bob_o.secret).unwrap(),
            Winner::Bob
        );

        // even ^ even = 0 -> Alice
        let g = game(&alice_e, &bob_e);
        assert_eq!(
            g.resolve(&alice_e.secret, &bob_e.secret).unwrap(),
            Winner::Alice
        );
    }

    #[test]
    fn every_limb_contributes_to_the_outcome() {
        // If only the first limb counted, a player could grind the other three
        // for free after committing to the first.
        let base = Secret::new([2, 4, 6, 8]);
        let flipped_last = Secret::new([2, 4, 6, 9]);
        let a = Player::new(hash(1), base);
        let b = Player::new(hash(2), bob_even());
        let g1 = game(&a, &b);
        let g2 = game(&Player::new(hash(1), flipped_last), &b);
        assert_ne!(
            g1.resolve(&base, &b.secret).unwrap(),
            g2.resolve(&flipped_last, &b.secret).unwrap()
        );
    }

    #[test]
    fn a_forged_reveal_is_rejected() {
        // The binding property: you cannot reveal a secret you did not commit.
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let forged = Secret::new([9, 9, 9, 9]);
        assert_eq!(
            g.resolve(&forged, &bob.secret),
            Err(RevealError::CommitmentMismatch { player: "alice" })
        );
        assert_eq!(
            g.resolve(&alice.secret, &forged),
            Err(RevealError::CommitmentMismatch { player: "bob" })
        );
    }

    #[test]
    fn neither_player_can_change_the_outcome_after_committing() {
        // Each player holds exactly one secret, so there is no second secret to
        // switch to after seeing the opponent's reveal. Any substitution is a
        // commitment mismatch, which is the property this asserts.
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let honest = g.resolve(&alice.secret, &bob.secret).unwrap();
        assert_eq!(honest, Winner::Bob);

        // Alice, losing, tries every alternative she could hope to pass off.
        for candidate in
            [Secret::new([2, 4, 6, 9]), Secret::new([1, 4, 6, 8]), Secret::new([0, 0, 0, 0])]
        {
            assert!(
                g.resolve(&candidate, &bob.secret).is_err(),
                "a substituted secret must not be accepted"
            );
        }
    }

    #[test]
    fn degenerate_terms_are_refused() {
        let secret = alice_even();
        let same = PlayerCommitment {
            pkh: hash(1),
            commitment: secret.commitment(),
        };
        // Identical commitments would collapse the hax z-set to one element.
        assert!(matches!(
            GameTerms::new(
                same.clone(),
                PlayerCommitment {
                    pkh: hash(2),
                    commitment: secret.commitment()
                },
                10,
                height(1)
            ),
            Err(CoinflipError::DuplicateCommitment)
        ));
        assert!(matches!(
            GameTerms::new(
                same.clone(),
                PlayerCommitment {
                    pkh: hash(1),
                    commitment: bob_odd().commitment()
                },
                10,
                height(1)
            ),
            Err(CoinflipError::DuplicatePlayer)
        ));
        assert!(matches!(
            GameTerms::new(
                same,
                PlayerCommitment {
                    pkh: hash(2),
                    commitment: bob_odd().commitment()
                },
                0,
                height(1)
            ),
            Err(CoinflipError::ZeroStake)
        ));
    }

    #[test]
    fn the_lock_root_is_stable_and_binds_every_term() {
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let root = g.lock_root().expect("hashes");
        assert_eq!(root, g.lock_root().expect("hashes"));

        // Changing the deadline changes the lock, so a player cannot fund a
        // note under terms the other did not agree to.
        let mut moved = g.clone();
        moved.refund_after = height(9_999);
        assert_ne!(root, moved.lock_root().expect("hashes"));

        // As does changing either commitment.
        let other = GameTerms::new(
            Player::new(hash(1), Secret::new([7, 7, 7, 7])).commit(),
            bob.commit(),
            g.stake_nicks,
            g.refund_after.clone(),
        )
        .unwrap();
        assert_ne!(root, other.lock_root().expect("hashes"));
    }

    #[test]
    fn the_first_name_derives_from_the_lock_root() {
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let expected = FirstName::from_lock_root(&g.lock_root().unwrap()).unwrap();
        assert_eq!(g.first_name().unwrap(), expected);
    }

    // --- branch satisfiability, checked with the driver's own lock evaluator ---

    fn context_with(secrets: &[&Secret], keys: &[Hash]) -> UnlockContext {
        let mut ctx = UnlockContext::new().with_signer_pkhs(keys.to_vec());
        for secret in secrets {
            ctx = ctx.with_preimage(secret.commitment(), secret.limbs().to_vec().concat_bytes());
        }
        ctx
    }

    trait ConcatBytes {
        fn concat_bytes(self) -> Vec<u8>;
    }
    impl ConcatBytes for Vec<u64> {
        fn concat_bytes(self) -> Vec<u8> {
            self.into_iter().flat_map(|v| v.to_le_bytes()).collect()
        }
    }

    #[test]
    fn settlement_needs_both_secrets_and_both_signatures() {
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let branch = g.settle_branch();
        let now = height(100);
        let origin = height(1);

        // Only Alice's secret and key: not enough.
        let only_alice = context_with(&[&alice.secret], std::slice::from_ref(&alice.pkh));
        assert!(matches!(
            check_spend_condition(&branch, &only_alice, &now, &origin),
            Err(UnspendableReason::MissingPreimage { .. })
        ));

        // Both secrets, one key: hashlock satisfied, threshold is not.
        let one_key = context_with(
            &[&alice.secret, &bob.secret],
            std::slice::from_ref(&alice.pkh),
        );
        assert!(matches!(
            check_spend_condition(&branch, &one_key, &now, &origin),
            Err(UnspendableReason::ThresholdUnmet { needed: 2, have: 1 })
        ));

        // Both secrets, both keys: settles.
        let both = context_with(
            &[&alice.secret, &bob.secret],
            &[alice.pkh.clone(), bob.pkh.clone()],
        );
        assert!(check_spend_condition(&branch, &both, &now, &origin).is_ok());
    }

    #[test]
    fn the_refund_branch_is_shut_until_the_deadline() {
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let branch = g.refund_branch();
        let origin = height(1);
        let both_keys = [alice.pkh.clone(), bob.pkh.clone()];

        let before = context_with(&[], &both_keys);
        assert!(matches!(
            check_spend_condition(&branch, &before, &height(499), &origin),
            Err(UnspendableReason::AbsoluteTimelockNotMet { .. })
        ));

        // At the deadline it opens — and notably needs no secrets, so a game
        // that never completed can still be unwound.
        assert!(check_spend_condition(&branch, &before, &height(500), &origin).is_ok());
    }

    #[test]
    fn a_losing_player_cannot_unilaterally_take_the_pot() {
        // The security property that matters: neither branch is satisfiable by
        // one player alone, at any height, even holding both revealed secrets.
        let (alice, bob) = players();
        let g = game(&alice, &bob);
        let origin = height(1);

        for (name, key) in [("alice", &alice.pkh), ("bob", &bob.pkh)] {
            let solo = context_with(&[&alice.secret, &bob.secret], std::slice::from_ref(key));
            for height_now in [height(1), height(499), height(500), height(100_000)] {
                for branch in [g.settle_branch(), g.refund_branch()] {
                    assert!(
                        check_spend_condition(&branch, &solo, &height_now, &origin).is_err(),
                        "{name} alone must never satisfy a branch at height {}",
                        height_now.0 .0
                    );
                }
            }
        }
    }
}
