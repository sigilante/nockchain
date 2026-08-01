# tx-driver

Turns a declarative transaction intent into a confirmed on-chain transaction,
exactly once, with a typed outcome correlated back to the caller.

It reuses the existing pieces rather than reimplementing them — `wallet-tx-builder`
for note selection and fee estimation, `nockchain-types` for lock and first-name
derivation, `nockapp-grpc`'s v2 `public_nockchain` client for submission — and
assembles them into one async, restart-durable pipeline.

```rust
let driver = TxDriver::new(
    TxDriverConfig { journal_dir, ..Default::default() },
    Arc::new(GrpcChainSource::connect_with_node(public, private, Some(&expected)).await?),
    Arc::new(signer),
).await?;

driver.recover().await?;                         // resume anything interrupted

match driver.submit(intent).await? {
    TxOutcome::Confirmed { tx_id, height, .. } => { /* on chain */ }
    TxOutcome::Submitted { tx_id, .. }         => { /* in the mempool */ }
    TxOutcome::Rejected  { reason, .. }        => { /* terminal — safe to roll back */ }
    TxOutcome::Failed    { error, .. }         => { /* status unknown — do NOT roll back */ }
}
```

## Pipeline

```
validate -> journal.accept -> read balance -> classify -> plan
   -> journal.planned -> sign -> validate signature -> journal.signed
   -> submit -> journal.submitted -> [confirm] -> journal.confirmed
```

Two orderings carry the correctness of the whole thing, and both are asserted by
tests:

- **`journal.signed` happens before `submit`.** A crash during submission leaves
  signed bytes on disk; recovery resubmits *exactly those*. Reversed, a crash
  between submitting and journalling would leave a live transaction with no
  record of it, and the next run would plan a second one against the same notes.
- **Nothing is re-planned after signing.** Because a transaction id is a digest
  over the signed transaction, resubmitting identical bytes is idempotent —
  at-least-once delivery of a content-addressed object is exactly-once in effect.

## Module map

| Module | What lives there |
|---|---|
| `intent` | `TxIntent`, `Destination`, `TxOutcome`, `IntentId` |
| `chain` | `ChainSource` trait, `GrpcChainSource`, `ChainConstants` |
| `notes` | Balance → candidates, `UnspendableReason`, `UnlockContext` |
| `build` | Intent → `PlanRequest` → `TxPlan`; `FeePolicy` enforcement |
| `sign` | `Signer` trait, `validate_signed`, `RemoteSigner` |
| `journal` | The durable write-ahead log and its state machine |
| `driver` | Orchestration — the file to read first |
| `nockapp` | `IODriverFn` adapter (feature `nockapp-driver`) |
| `testing` | In-memory mocks (feature `testing`) |

## Trait boundaries

Every external authority sits behind a trait, which is what makes the pipeline
testable without a node or a wallet.

**`ChainSource`** — balances, fee constants, submission, confirmation. The
production impl talks to the **v2** service; v1's `wallet_send_transaction` still
takes a `v0::RawTx` and cannot carry a witness-era transaction.

**`Signer`** — the only thing that touches key material. An intent names a
`SpendCondition`, never a private key, so secrets never enter kernel state, an
on-disk checkpoint, or a logged effect. A `SignRequest` carries the plan, the
notes, and the spend conditions, so a signer can verify what it is approving
rather than trusting a summary.

Signer output is not trusted: `validate_signed` recomputes the transaction id,
checks inputs, outputs and fee against the plan, and Schnorr-verifies every
signature present. A mismatch is `Rejected` — terminal on purpose, because a
signer that substitutes a transaction once will do it again.

## Things worth knowing before reviewing

**`Rejected` vs `Failed` is the rollback contract.** `Rejected` is terminal and
provable — it can only be produced before submission (or on an outright network
refusal), so a caller may safely undo optimistic state. `Failed` says the driver
could not finish and says *nothing* about whether a spend is live. Collapsing
these into one error is what made the predecessor unsafe to build on.

**Unspendable notes are reported, never dropped.** A note the driver cannot spend
comes back as a typed `UnspendableReason` — missing preimage, unmet timelock,
threshold shortfall — so "insufficient funds" is falsifiable and a UI can say
*why* money is unreachable.

**No clap, no argv, no process exit.** `TxDriverConfig` is a plain struct with a
`Default`. Any CLI layer belongs in a consumer binary.

**Fee constants are read from the node** when you use `connect_with_node`, and
can be checked against an expected set so a fork is caught at connect time rather
than as a silently underpriced transaction.

**Signing against a real wallet kernel** is available behind the `kernel-signer`
feature. `KernelSigner` boots the Hoon wallet, seeds it with keys and with the
balance the driver planned against, and pins it to that plan: inputs are named
explicitly, the fee is passed as a number, and *every* output — change included —
is handed over as a `%lock-root` order, so the kernel's own change logic has
nothing left to compute. The signed transaction comes back through the kernel's
`%file` effect and is decoded in memory; nothing is written to disk.

The feature is off by default because it pulls in the wallet kernel image and
the prover hot state, which a host that signs remotely has no use for.

> **Requires a current `assets/wal.jam`.** That file is a local build artifact
> (gitignored), and `make` will not notice when it goes stale: `HOON_SRCS` in the
> Makefile is written `$(find ...)` rather than `$(shell find ...)`, so it
> expands to nothing and every jam rule's source dependency list is empty. A jam
> is therefore only rebuilt when its own entry point changes — never when a
> library under it does.
>
> A kernel older than the `multisig` field `create-tx-cause` grew in
> `hoon/apps/wallet/lib/types.hoon` rejects the poke outright, as it does the
> `nockchain-wallet` CLI's own `create-tx`. Rebuild with `make assets/wal.jam`
> (`rm` it first, or the rule may consider it up to date). A stale kernel shows
> up as `the wallet kernel built no transaction. It said: ## Poke failed`.

## Not implemented

- **Spending from multi-branch lock trees.** `Recipient::to_tree` lets you pay
  *into* one, but `SpendConditionMatcher` derives first-names via the
  single-condition path, so tree-locked notes are not recognised as inputs. They
  currently classify as `LockNotDeclared`, which is misleading — the driver
  cannot represent the lock, rather than the caller having omitted it.
- **Consensus validation.** `validate_signed` polices the *signer*; it does not
  prove a transaction is spendable. The authoritative check is
  `+validate-with-context:spends` in `hoon/common/tx-engine-1.hoon`, which returns
  a typed reason and is not yet wired in. Until it is, `chain::classify_submit_error`
  decides terminal-vs-retryable by matching the node's error string, which is a
  heuristic.
- **A live-node end-to-end test.** Everything is covered against in-memory mocks.

## Testing

```sh
cargo test -p tx-driver                          # library core, in-memory
cargo test -p tx-driver --features kernel-signer # adds the wallet-kernel suite
cargo clippy -p tx-driver --all-targets
```

The mocks are available downstream behind the `testing` feature. `MockSigner`
can be told to misbehave in specific ways (redirect outputs, inflate the fee, add
an output, decline, go unavailable) so the driver's defences are exercised by the
same code path as the good case.

See [`crates/coinflip`](../coinflip) for a worked example: a two-party
commit–reveal game whose stake note is a two-branch lock, funded through the
driver.
