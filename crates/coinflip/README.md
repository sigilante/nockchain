# `coinflip`

A two-party commit–reveal coinflip, settled with `tx-driver`.

```sh
cargo run -p coinflip --bin coinflip-demo
cargo test -p coinflip
```

The demo runs against `tx_driver::testing::MockChainSource`, so it needs no node
and moves no real money. Every hash, lock root, and first-name it prints is
computed with the same code the wallet and the Hoon tx-engine use, so the
cryptography is real even though the chain is not.

## The protocol

```
1. Alice picks secret a, publishes h(a).
2. Bob picks secret b, publishes h(b).      <- after seeing h(a), never a
3. Both fund the stake note.
4. Alice reveals a.
5. Bob reveals b.

outcome = parity(a) XOR parity(b):  0 -> Alice,  1 -> Bob
```

Step 2 is what makes it fair: Bob commits before seeing Alice's *secret*, so he
cannot pick `b` to steer the result, and neither party can produce a second
preimage for a published hash. Each player holds exactly one secret, so revealing
second confers nothing.

## The lock

```
Lock::V2
  branch 0 (settle): Hax{h(a), h(b)}       AND Pkh{m=2, {alice, bob}}
  branch 1 (refund): Tim{abs.min=deadline} AND Pkh{m=2, {alice, bob}}
```

Branch 0 opens only when *both* secrets are public — `hax` requires every
preimage in its set, not any one of them — and only with both signatures.
Branch 1 returns the stake if the game never completes.

`crates/coinflip/src/lib.rs` tests every case of this against the driver's own
lock evaluator (`tx_driver::notes::check_spend_condition`), including that
neither player alone can satisfy either branch at any height, even holding both
revealed secrets.

## What it guarantees, and what it does not

**The outcome is enforced.** Unbiased, binding, no equivocation, no last-mover
advantage.

**The payout is cooperative.** Settlement needs both signatures, so a losing
player can refuse to sign; the stake then returns to both at the refund
deadline. Cheating is *griefable but not profitable* — it denies the winner
their winnings, it does not transfer them to the cheat.

Closing that gap needs per-player bonds in separate notes, forfeitable on
non-cooperation. It is not implemented here. The reason it cannot be done inside
the lock is structural: Nockchain locks are predicates on *whether* a note may be
spent, never covenants on *where* its value goes, and no lock can compute
`parity(a XOR b)`.

### A construction that does not work

An earlier draft had each player commit to *two* secrets, one per outcome, with a
four-branch lock naming the winner for each combination — an appealing design,
because the XOR table falls straight out of the branch structure. It is broken:
whoever reveals second sees the opponent's secret and then chooses whichever of
their own two secrets wins. One secret per player is the fix, and it is why the
lock cannot select the winner.

## Status

Funding a game works end to end through the driver. *Spending* the stake note
does not yet, for two reasons outside this crate:

- `tx-driver`'s `SpendConditionMatcher` derives first-names via the
  single-condition path, so it does not recognise notes locked to a multi-branch
  tree. Paying *into* one works (`Recipient::to_tree`); spending *out of* one
  needs the matcher to accept a `Lock` and carry the chosen branch.
- Witnessing a tree branch needs a `LockMerkleProof`, and there is no signer that
  can produce one — see `crates/tx-driver/KERNEL_SIGNER_SPEC.md`.
