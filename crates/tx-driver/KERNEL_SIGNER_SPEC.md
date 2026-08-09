# `KernelSigner` — implementation spec

**Audience.** A session starting fresh on branch `tx-driver`, with no prior context.

**Goal.** Implement `tx_driver::sign::KernelSigner`: a [`Signer`] backed by a
resident Hoon wallet kernel. It is the last unimplemented piece of the driver;
everything else is written and tested (88 tests, `cargo test -p tx-driver`).

---

## 1. Orientation — read these first

| What | Where |
|---|---|
| The trait to implement | `crates/tx-driver/src/sign.rs` — `Signer`, `SignRequest`, `SignError` |
| What a signer is checked against | `crates/tx-driver/src/sign.rs::validate_signed` |
| What produced the plan | `crates/tx-driver/src/build.rs` — `TxPlan` |
| Where the signer is called | `crates/tx-driver/src/driver.rs::TxDriver::sign` |
| A working reference signer | `crates/tx-driver/src/testing.rs` — `MockSigner` |
| The poke to reproduce | `crates/nockchain-wallet/src/create_tx.rs:2048` — `encode_create_tx_request` |
| The parity check to reuse | `crates/nockchain-wallet/src/create_tx.rs:12` — `ensure_manual_planner_parity` |
| How the CLI drives a resident kernel | `crates/nockchain-wallet/src/main.rs:1115-1160` (derive-child-batch) |
| The wallet kernel | `hoon/apps/wallet/wallet.hoon`, booted from `kernels_open_wallet::KERNEL` |

The contract to satisfy:

```rust
#[async_trait]
pub trait Signer: Send + Sync {
    async fn signer_pkhs(&self) -> Result<Vec<Hash>, SignError>;
    async fn sign(&self, request: SignRequest) -> Result<v1::RawTx, SignError>;
}
```

---

## 2. Why this needs a design at all

Rust can *verify* signatures (`nockchain-types/src/tx_engine/v1/signatures.rs`)
but cannot *produce* them. Schnorr signing lives only in the Hoon wallet kernel.
So the signer must hold a booted kernel and poke it.

Two facts shape the design, and both are easy to get wrong:

**The kernel does its own planning.** `create-tx` is not "sign this transaction".
It is "build and sign a transaction", and the kernel selects notes and computes
a fee itself. The driver has *already* planned. If the two disagree, the signer
returns a transaction the driver did not ask for and `validate_signed` rejects
it — correctly, but uselessly.

The fix is the one the wallet CLI already uses: constrain the kernel to the
driver's plan by passing the selected note names explicitly and pinning the fee.
`Wallet::create_tx_with_planner` does exactly this, and
`ensure_manual_planner_parity` asserts the two agree. See §5.

**The kernel is stateful.** `create-tx` reads keys and balance from kernel state.
A freshly booted kernel knows nothing, and will fail or silently produce an empty
selection. The signer must seed it. See §4.

### Correction to an earlier claim

An earlier note on this branch said `NockApp::run()` "runs to completion", implying
a kernel could only serve one command. That is wrong, and it made this look harder
than it is. `NockApp::run()` (`crates/nockapp/src/nockapp/mod.rs:366`) is a loop
that ends only when a driver calls `handle.exit.exit(..)`. The wallet CLI is
one-shot because *its* drivers exit after one command, not because the runtime
requires it.

A resident signer therefore just installs a driver that never exits. Consequences:

- **The `nockchain-wallet` library target is not a prerequisite.** `KernelSigner`
  can boot `kernels_open_wallet::KERNEL` into a `NockApp` directly. The lib target
  is still worth doing so the poke encoder can be *reused* rather than duplicated
  (§8), but it is no longer blocking.
- The work is smaller than previously scoped: roughly one new module.

---

## 3. Architecture

```text
 TxDriver ──sign(SignRequest)──> KernelSigner
                                      │  mpsc::Sender<SignJob>
                                      ▼
                            ┌────────────────────────┐
                            │ resident IO driver     │  never exits
                            │  loop {                │
                            │    recv SignJob        │
                            │    poke create-tx      │
                            │    drain effects       │
                            │    reply on oneshot    │
                            │  }                     │
                            └────────────────────────┘
                                      │
                            NockApp::run() on a spawned task
                                      │
                             Hoon wallet kernel
```

```rust
pub struct KernelSigner {
    jobs: mpsc::Sender<SignJob>,
    pkhs: Vec<Hash>,                 // cached at construction
    _kernel: tokio::task::JoinHandle<()>,  // the run() task
}

struct SignJob {
    request: SignRequest,
    reply: oneshot::Sender<Result<v1::RawTx, SignError>>,
}
```

Requests are serialised through the channel. That is deliberate: the kernel is a
single-threaded state machine, and the driver's concurrency lives at the intent
level, not inside the signer. A `sign()` call that waits behind another is fine;
`TxDriver` runs each intent on its own task.

### Construction

```rust
impl KernelSigner {
    pub async fn new(config: KernelSignerConfig) -> Result<Self, SignError>;
}

pub struct KernelSignerConfig {
    /// Wallet kernel state directory. Reused across restarts.
    pub data_dir: PathBuf,
    /// Master key material, supplied once at boot. See §4.1 on why this is a
    /// separate concern from the intent.
    pub key_source: KeySource,
    /// Which derived keys may sign: (index, hardened) pairs.
    pub sign_keys: Vec<(u64, bool)>,
    /// Fakenet/devnet constants, when not running against mainnet.
    pub chain_constants: Option<BlockchainConstants>,
    /// How long to wait for the kernel to answer one sign request.
    pub timeout: Duration,
}
```

Boot follows `crates/nockchain-wallet/src/main.rs`: `NockStackSize::Tiny`, hot
state from `zkvm_jetpack::hot::produce_prover_hot_state()`.

---

## 4. Seeding kernel state

Both of these must happen before the first `create-tx`, and neither is optional.

### 4.1 Keys

Poke the wallet kernel with the master key (`import-keys` / `keygen` / seed
phrase, depending on `KeySource`). Then read the derived public-key hashes back
and cache them for `signer_pkhs()`.

`signer_pkhs()` is not cosmetic: `TxDriver` builds its `UnlockContext` from it
(`driver.rs::unlock_context`), so a note requiring a key the kernel does not hold
is reported as `UnspendableReason::ThresholdUnmet` during *planning* rather than
blowing up at signing time. Returning the wrong set here degrades error quality
throughout the pipeline.

Read them via the existing peek helpers, which are the reference for the peek
paths: `Wallet::peek_signing_keys`, `peek_active_signer_keys`,
`peek_master_signing_key` (`crates/nockchain-wallet/src/create_tx.rs:730-800`).

### 4.2 Balance

`create-tx` selects from the balance held in kernel state. The driver already has
the notes — they are in `SignRequest::notes` — so the signer must push them in
rather than have the kernel fetch them independently. Two sources would mean two
views of the chain and a plan the kernel cannot reproduce.

Use `Wallet::update_balance_grpc_poke` (`create_tx.rs:2175`), which encodes a
`v1::BalanceUpdate`. Build that from `SignRequest::notes` plus the height the
driver planned at.

> **Design note.** `SignRequest` currently carries `Vec<CandidateNote>`, not a
> `BalanceUpdate`, so the height and block id are not available to the signer.
> Either add them to `SignRequest` (preferred — a signer that wants to verify a
> timelock needs the height anyway) or have `KernelSignerConfig` hold a
> `ChainSource` to re-read. **Do not** let the kernel fetch its own balance over
> gRPC: that reintroduces the two-views problem.

---

## 5. Constraining the kernel to the driver's plan

This is the core of the implementation.

Encode the poke exactly as `Wallet::encode_create_tx_request` does
(`create_tx.rs:2048`). The noun is a 10-tuple:

```
[names order fee allow-low-fee sign-key refund include-data save-raw-tx note-selection multisig]
```

Field by field, with what `KernelSigner` must put there:

| Field | Source | Notes |
|---|---|---|
| `names` | `plan.assembled.inputs[].note.name` | **The whole mechanism.** Formatted `"[<first-b58> <last-b58>]"` comma-joined — `Wallet::format_note_names_for_create_tx` (`create_tx.rs:623`). Pins the kernel to the driver's selection. |
| `order` | `plan.assembled.outputs` | Recipient lock roots and amounts. Note the refund output is *in* `outputs`; check whether the kernel expects it in `order` or derives it from `refund`. |
| `fee` | `plan.assembled.fee` | Pinned, not recomputed. |
| `allow-low-fee` | `false` | The driver's fee is planner-computed; if the kernel thinks it is low, that is a parity failure worth surfacing, not suppressing. |
| `sign-key` | `config.sign_keys` | `Wallet::encode_sign_keys` (`create_tx.rs:2166`). |
| `refund` | refund lock's pkh | `Option<String>` base58. Derive from the intent's refund lock. |
| `include-data` | `false` | Matches `build.rs`, which sets `include_data: false` in the `PlanRequest`. Must agree or word counts diverge and the fee changes. |
| `save-raw-tx` | see §6 | Controls what the `%file` effect contains. |
| `note-selection` | manual/custom | Must correspond to the explicit `names` list. |
| `multisig` | `Some(..)` for m-of-n inputs | Threshold + participant pkhs, so the kernel can rebuild an input lock whose note-data omits it. Derive from `plan.spend_conditions`. |

After decoding the signed transaction, run
`ensure_manual_planner_parity(requested_names, planned_names)` — or an equivalent
— before returning. It is cheap, and it turns a subtle fee/selection divergence
into a clear message instead of an opaque `SignerMismatch` two layers up.

`validate_signed` will catch a divergence regardless. The parity check exists to
make the *diagnosis* good.

---

## 6. Capturing the signed transaction

The wallet kernel does not return the transaction from the poke. It emits a
`[%file %write <path> <jam>]` effect, and the CLI writes it to disk
(`Wallet::apply_wallet_effects_locally`, `create_tx.rs:1014`).

**Do not write to disk.** Decode the jam in memory. Writing it means a plaintext
signed transaction on disk, a temp-file race between concurrent signs, and a
filesystem dependency in a code path that has no other reason to touch the disk.

The resident driver loop, modelled on `main.rs:1125-1155`:

```rust
handle.poke(OnePunchWire::Poke.to_wire(), poke).await?;   // Ack or Nack

let mut effects = Vec::new();
loop {
    let effect = handle.next_effect().await?;
    let is_exit = is_exit_effect(&effect);
    effects.push(effect);
    if is_exit { break; }
}
```

⚠️ **The `%exit` terminator is a problem for a resident kernel.** The CLI relies
on the kernel emitting `%exit` to know a command finished. If the wallet kernel
emits `%exit` after `create-tx`, and any installed driver forwards it to
`handle.exit`, `NockApp::run()` returns and the kernel dies after one signature.

Resolve this early — it decides the shape of the whole module:

1. Confirm whether `create-tx` emits `%exit`. If it does, treat it as an
   end-of-response marker inside the signer's own loop and **never** call
   `handle.exit`. Do not install `exit_driver`.
2. If some other installed driver would forward it, do not install that driver.
3. If the kernel's `%exit` is unavoidable and fatal, fall back to a
   kernel-per-signature model: boot, poke, capture, drop. Slower, but correct,
   and it still satisfies the trait. Prefer this over a subtly broken resident
   kernel.

Decode the captured jam with `journal::cue_raw_tx` if `save-raw-tx` yields a bare
`RawTx`. If it yields the richer saved-transaction envelope, follow
`Wallet::decode_transaction_spends_from_bytes` (`create_tx.rs:1187`), which
already handles that layout — version, name, spends, display, witness-data.

Map failures onto `SignError` (`sign.rs`), and get this right, because
`is_terminal()` decides whether `TxDriver` reports a terminal `Rejected` or a
retryable `Failed`:

| Situation | Variant | Terminal |
|---|---|---|
| Kernel `Nack`ed the poke | `Declined` | yes |
| No key for a required pkh | `NoSuchKey` | yes |
| Effect jam did not decode | `Undecodable` | yes |
| Kernel task died, channel closed, timeout | `Unavailable` | **no** |

The timeout case matters: a signer that hangs must produce `Unavailable`, so the
intent stays recoverable rather than being falsely marked terminal.

---

## 7. Tests

The signer conformance suite should run against `KernelSigner` and `MockSigner`
alike — same assertions, different backend — so the mock stays honest.

Required:

1. **Faithful round trip.** Plan a payment, sign, `validate_signed` passes.
2. **Parity.** The kernel selects exactly the driver's inputs and charges exactly
   the driver's fee. Assert on the returned transaction, not on logs.
3. **Residency.** Sign three transactions through one `KernelSigner` and assert
   all three succeed. This is the test that catches the `%exit` problem.
4. **Concurrency.** Two `TxDriver::submit` calls in flight against one signer;
   both complete, with distinct transaction ids and correct correlation ids.
5. **`signer_pkhs` is truthful.** A note locked to a key the kernel does not hold
   is classified `ThresholdUnmet` at planning time and never reaches the signer.
6. **Timeout.** A wedged kernel yields `SignError::Unavailable`, and the intent
   stays in the journal as recoverable.
7. **No disk writes.** Sign with a `data_dir` under `tempfile::tempdir()` and
   assert no `.tx` file appears.
8. **Multisig.** An m-of-n input signs correctly with the `multisig` payload set.

Existing fixtures to lean on: `crates/nockchain-wallet/src/tests.rs` boots wallet
kernels and has known-good keys and notes; `crates/nockchain-testkit/src/scenario.rs`
is the broader harness.

---

## 8. Optional: the `nockchain-wallet` library target

Only needed to *reuse* `encode_create_tx_request` and friends instead of
duplicating ~120 lines of poke encoding. Worth doing — a duplicated encoder will
drift from the kernel it targets, which is the exact failure mode this crate
avoids elsewhere by reusing `wallet-tx-builder`.

Low-risk approach, verified against the current layout:

1. `cp src/main.rs src/lib.rs`.
2. In `lib.rs`, change `#[tokio::main] async fn main()` to `pub async fn run()`.
   Leave everything else, including `mod tests`, in place.
3. Replace `src/main.rs` with:
   ```rust
   #[tokio::main]
   async fn main() -> Result<(), nockapp::NockAppError> {
       nockchain_wallet::run().await
   }
   ```
4. Promote to `pub` only what `tx-driver` needs: `Wallet::new`,
   `encode_create_tx_request`, `encode_sign_keys`,
   `format_note_names_for_create_tx`, `update_balance_grpc_poke`,
   `decode_transaction_spends_from_bytes`, `ensure_manual_planner_parity`.

This is a rename plus visibility changes, not a code move. The wallet's own tests
come along and must still pass — run `cargo test -p nockchain-wallet` before and
after and compare.

Do this **after** `KernelSigner` works against a directly-booted kernel, so the
two changes can be reviewed and reverted independently.

---

## 9. Definition of done

- `KernelSigner` implements `Signer` and passes the §7 suite.
- `cargo test -p tx-driver` and `cargo test -p nockchain-wallet` both green.
- `cargo clippy -p tx-driver --all-targets` clean (the workspace denies
  `unwrap_used` outside tests and `needless_borrow` everywhere).
- The crate-level docs no longer list `KernelSigner` as unimplemented.
- No plaintext signed transaction ever touches the disk.
