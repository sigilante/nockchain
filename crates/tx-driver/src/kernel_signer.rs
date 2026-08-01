//! [`KernelSigner`] — a [`Signer`] backed by a resident Hoon wallet kernel.
//!
//! Rust can *verify* signatures ([`nockchain_types::tx_engine::v1::signatures`])
//! but cannot *produce* them: Schnorr signing lives only in the Hoon wallet.
//! So this signer holds a booted wallet kernel and pokes it.
//!
//! # The problem this module actually solves
//!
//! The kernel's `create-tx` is not "sign this transaction". It is "build *and*
//! sign a transaction": given a loose request it selects its own notes,
//! computes its own fee, and decides its own change output. The driver has
//! already done all three. If the two disagree the signer returns a transaction
//! the driver never asked for, and [`crate::sign::validate_signed`] rejects it —
//! correctly, but uselessly.
//!
//! Everything here is in service of pinning the kernel to the driver's plan:
//!
//! - **Inputs** are named explicitly, so the kernel's selector has exactly one
//!   legal answer.
//! - **The fee** is passed as a number, not a policy.
//! - **Every output, including the change,** is passed as a `%lock-root` order.
//!   That is the whole trick, and it is worth spelling out: the driver's plan
//!   already contains the change output, so if the orders are handed over
//!   *complete*, then `inputs − orders − fee = 0` and the kernel's own refund
//!   logic drops out (`+create-spends-1` in `tx-builder.hoon` omits the refund
//!   order when the remainder is zero). The alternative — telling the kernel
//!   where to send change and letting it compute the amount — reintroduces the
//!   second opinion this design exists to avoid.
//!
//!   `%lock-root` also carries no note-data, which is what the driver plans
//!   ([`crate::build`] sets `include_data: false`), and it can express a
//!   destination the `%pkh` and `%multisig` orders cannot: a
//!   [`crate::intent::Destination::Tree`] or a bare lock root.
//!
//! # Residency
//!
//! [`nockapp::NockApp::poke_timeout`] returns the effects of one poke directly.
//! There is no need for an IO driver, and therefore no need for
//! [`nockapp::NockApp::run`] — which is what makes the wallet CLI one-shot, and
//! which would have made `%exit` handling load-bearing. The kernel simply lives
//! in a task that owns it and serves sign jobs off a channel.
//!
//! Requests are serialised through that channel on purpose. The kernel is a
//! single-threaded state machine; the driver's concurrency lives at the intent
//! level, and `TxDriver` runs each intent on its own task, so a `sign()` that
//! waits behind another is fine.
//!
//! # What never happens
//!
//! The kernel reports a built transaction by emitting `[%file %write path jam]`,
//! and the wallet CLI writes it to disk. This module decodes the jam in memory
//! and never touches the filesystem: writing it would mean a plaintext signed
//! transaction on disk, a temp-file race between concurrent signs, and a
//! filesystem dependency in a code path with no other reason to have one.

use std::path::PathBuf;
use std::time::Duration;

use async_trait::async_trait;
use nockapp::kernel::boot::{self, NockStackSize};
use nockapp::noun::slab::NounSlab;
use nockapp::utils::bytes::Byts;
use nockapp::utils::make_tas;
use nockapp::wire::{Wire, WireRepr};
use nockapp::{Bytes, CrownError, NockApp, NockAppError};
use nockchain_math::belt::Belt;
use nockchain_math::zoon::zmap::ZMap;
use nockchain_types::blockchain_constants::BlockchainConstants;
use nockchain_types::tx_engine::common::{Hash, Name, Signature, Version};
use nockchain_types::tx_engine::v1;
use nockvm::jets::cold::Nounable;
use nockvm::noun::{Cell, Noun, NounAllocator, D, T};
use noun_serde::{NounDecode, NounEncode};
use tokio::sync::{mpsc, oneshot};
use tracing::{debug, info, warn};

use crate::sign::{SignError, SignRequest, Signer};

/// The wire every poke this module sends is tagged with.
///
/// The wallet kernel dispatches on `[%poke ?(%one-punch %sys %wallet %file) ..]`
/// and refuses anything else, so this is not decorative.
struct WalletPokeWire;

impl Wire for WalletPokeWire {
    const VERSION: u64 = 1;
    const SOURCE: &'static str = "one-punch";
}

fn wire() -> WireRepr {
    WalletPokeWire.to_wire()
}

/// Master key material for the wallet kernel, supplied once at boot.
///
/// This is deliberately separate from the intent. An intent names the *lock* it
/// spends from; which keys open that lock is the signer's business and nobody
/// else's, and key material must never travel in-band through a request.
#[derive(Clone)]
pub enum KeySource {
    /// Generate a fresh master key from caller-supplied entropy and salt.
    Generate { entropy: [u8; 32], salt: [u8; 16] },
    /// Import a BIP39-style seed phrase.
    SeedPhrase { phrase: String, version: u64 },
    /// Import an extended key (`zprv`/`zpub`).
    ExtendedKey(String),
    /// The kernel state at `data_dir` already holds keys. Nothing is poked.
    Existing,
}

impl std::fmt::Debug for KeySource {
    /// Redacted on purpose: a `Debug` that prints a seed phrase turns every
    /// stray `{:?}` and every panic message into a key leak.
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let variant = match self {
            Self::Generate { .. } => "Generate",
            Self::SeedPhrase { .. } => "SeedPhrase",
            Self::ExtendedKey(_) => "ExtendedKey",
            Self::Existing => "Existing",
        };
        write!(f, "KeySource::{variant}(<redacted>)")
    }
}

/// How to boot and drive the wallet kernel.
#[derive(Debug, Clone)]
pub struct KernelSignerConfig {
    /// Wallet kernel state directory, reused across restarts. `None` boots an
    /// ephemeral kernel whose state does not outlive the process — correct for
    /// tests, wrong for anything holding real keys.
    pub data_dir: Option<PathBuf>,
    /// Master key material.
    pub key_source: KeySource,
    /// Which derived keys may sign, as `(index, hardened)` pairs. Empty means
    /// the master key.
    pub sign_keys: Vec<(u64, bool)>,
    /// Fakenet/devnet constants. `None` leaves the kernel on mainnet defaults.
    pub chain_constants: Option<BlockchainConstants>,
    /// How long to wait for the kernel to answer one *sign* request. On expiry
    /// the signer reports [`SignError::Unavailable`], which is non-terminal, so
    /// the intent stays recoverable instead of being falsely written off.
    ///
    /// This does not bound [`KernelSigner::new`]. Booting a kernel and
    /// generating a key are far slower than answering a poke, so holding them
    /// to a signing budget would force the budget to be useless for signing.
    /// Construction is a single await the caller owns, so a caller who wants it
    /// bounded can wrap it in `tokio::time::timeout` — which is not an option
    /// for the per-request path, because that runs behind a channel.
    pub timeout: Duration,
}

impl Default for KernelSignerConfig {
    fn default() -> Self {
        Self {
            data_dir: None,
            key_source: KeySource::Existing,
            sign_keys: Vec::new(),
            chain_constants: None,
            timeout: Duration::from_secs(300),
        }
    }
}

/// One unit of work for the kernel task.
struct SignJob {
    request: SignRequest,
    reply: oneshot::Sender<Result<v1::RawTx, SignError>>,
}

/// A [`Signer`] backed by a resident Hoon wallet kernel.
pub struct KernelSigner {
    jobs: mpsc::Sender<SignJob>,
    pkhs: Vec<Hash>,
    /// The task owning the kernel.
    ///
    /// Held for diagnostics only — it is *not* what shuts the kernel down.
    /// Dropping a `JoinHandle` detaches the task rather than aborting it; what
    /// actually ends the loop is `jobs` being dropped along with this struct,
    /// which closes the channel, which makes `recv` return `None`, which drops
    /// the `NockApp`. Aborting would be worse: it could cut the task off
    /// mid-poke and leave the kernel's on-disk state torn.
    _kernel: tokio::task::JoinHandle<()>,
}

impl KernelSigner {
    /// Boots a wallet kernel, seeds it with keys, and starts serving.
    ///
    /// The derived public-key hashes are read back and cached here rather than
    /// peeked per call, because [`Signer::signer_pkhs`] is on the *planning*
    /// path: `TxDriver` builds its [`crate::notes::UnlockContext`] from it, so
    /// a note needing a key this kernel does not hold is reported as a
    /// threshold shortfall during planning instead of exploding at signing
    /// time.
    pub async fn new(config: KernelSignerConfig) -> Result<Self, SignError> {
        let timeout = config.timeout;
        let mut app = boot_wallet(&config).await?;

        if let Some(constants) = &config.chain_constants {
            setup_poke(&mut app, fakenet_poke(constants)).await?;
        }

        seed_keys(&mut app, &config.key_source).await?;

        let pkhs = read_signer_pkhs(&mut app).await?;
        if pkhs.is_empty() {
            return Err(SignError::NoSuchKey(
                "the wallet kernel holds no signing keys after seeding; check `key_source`".into(),
            ));
        }
        info!(keys = pkhs.len(), "kernel signer ready");

        let sign_keys = config.sign_keys.clone();
        let (jobs, mut inbox) = mpsc::channel::<SignJob>(32);
        let kernel = tokio::spawn(async move {
            while let Some(job) = inbox.recv().await {
                let result = sign_one(&mut app, &job.request, &sign_keys, timeout).await;
                // A dropped receiver means the caller gave up. The transaction
                // was built but never left this process, so there is nothing to
                // clean up — but it is worth saying out loud, because the
                // kernel did the work.
                if job.reply.send(result).is_err() {
                    warn!(
                        intent = %job.request.intent_id,
                        "sign result discarded: the caller stopped waiting"
                    );
                }
            }
            debug!("kernel signer shutting down: no more senders");
        });

        Ok(Self {
            jobs,
            pkhs,
            _kernel: kernel,
        })
    }
}

#[async_trait]
impl Signer for KernelSigner {
    async fn signer_pkhs(&self) -> Result<Vec<Hash>, SignError> {
        Ok(self.pkhs.clone())
    }

    async fn sign(&self, request: SignRequest) -> Result<v1::RawTx, SignError> {
        let (reply, answer) = oneshot::channel();
        self.jobs
            .send(SignJob { request, reply })
            .await
            .map_err(|_| SignError::Unavailable("the wallet kernel task has stopped".into()))?;
        answer.await.map_err(|_| {
            SignError::Unavailable("the wallet kernel task dropped the request".into())
        })?
    }
}

// ---------------------------------------------------------------------------
// Boot and seeding
// ---------------------------------------------------------------------------

async fn boot_wallet(config: &KernelSignerConfig) -> Result<NockApp, SignError> {
    let mut cli = boot::default_boot_cli(config.data_dir.is_none());
    // The wallet kernel is small; the wallet CLI runs it on `Tiny` too.
    cli.stack_size = NockStackSize::Tiny;
    if config.data_dir.is_none() {
        cli.ephemeral = true;
    }

    let hot_state = zkvm_jetpack::hot::produce_prover_hot_state();
    boot::setup(
        kernels_open_wallet::KERNEL,
        cli,
        hot_state.as_slice(),
        "wallet",
        config.data_dir.clone(),
    )
    .await
    .map_err(|err| SignError::Unavailable(format!("wallet kernel failed to boot: {err}")))
}

async fn seed_keys(app: &mut NockApp, source: &KeySource) -> Result<(), SignError> {
    let mut slab: NounSlab = NounSlab::new();
    let cause = match source {
        KeySource::Existing => return Ok(()),
        KeySource::Generate { entropy, salt } => {
            let entropy = byts_noun(&mut slab, entropy);
            let salt = byts_noun(&mut slab, salt);
            command(&mut slab, "keygen", &[entropy, salt])
        }
        KeySource::SeedPhrase { phrase, version } => {
            let phrase = make_tas(&mut slab, phrase).as_noun();
            let version = version.to_noun(&mut slab);
            command(&mut slab, "import-seed-phrase", &[phrase, version])
        }
        KeySource::ExtendedKey(key) => {
            let key = make_tas(&mut slab, key).as_noun();
            command(&mut slab, "import-extended", &[key])
        }
    };
    slab.set_root(cause);
    setup_poke(app, slab).await?;
    Ok(())
}

/// Reads the derived public-key hashes the kernel can sign for.
///
/// Mirrors the wallet CLI's fallback chain (`resolve_planner_signer_keys`):
/// tracked signing keys first, then active signer entries, then the master key.
/// A kernel seeded by `keygen` populates the first; one seeded by watching an
/// address may only populate the last.
async fn read_signer_pkhs(app: &mut NockApp) -> Result<Vec<Hash>, SignError> {
    let mut keys = peek_hashes(app, "signing-keys").await?;
    if keys.is_empty() {
        if let Some(master) = peek_hash(app, "master-signing-key").await? {
            keys.push(master);
        }
    }
    keys.sort_by_key(Hash::to_array);
    keys.dedup_by(|left, right| left.to_array() == right.to_array());
    Ok(keys)
}

async fn peek_hashes(app: &mut NockApp, path_tag: &str) -> Result<Vec<Hash>, SignError> {
    let result = peek(app, path_tag).await?;
    let space = result.noun_space();
    let decoded: Option<Option<Vec<Hash>>> =
        unsafe { <Option<Option<Vec<Hash>>>>::from_noun(result.root(), &space) }
            .map_err(|err| SignError::Undecodable(format!("{path_tag} peek: {err}")))?;
    Ok(decoded.flatten().unwrap_or_default())
}

async fn peek_hash(app: &mut NockApp, path_tag: &str) -> Result<Option<Hash>, SignError> {
    let result = peek(app, path_tag).await?;
    let space = result.noun_space();
    let decoded: Option<Option<Hash>> =
        unsafe { <Option<Option<Hash>>>::from_noun(result.root(), &space) }
            .map_err(|err| SignError::Undecodable(format!("{path_tag} peek: {err}")))?;
    Ok(decoded.flatten())
}

async fn peek(app: &mut NockApp, path_tag: &str) -> Result<NounSlab, SignError> {
    let mut slab: NounSlab = NounSlab::new();
    let tag = make_tas(&mut slab, path_tag).as_noun();
    let path = T(&mut slab, &[tag, D(0)]);
    slab.set_root(path);
    app.peek(slab)
        .await
        .map_err(|err| classify(err, &format!("peek {path_tag}")))
}

// ---------------------------------------------------------------------------
// Signing one request
// ---------------------------------------------------------------------------

async fn sign_one(
    app: &mut NockApp,
    request: &SignRequest,
    sign_keys: &[(u64, bool)],
    timeout: Duration,
) -> Result<v1::RawTx, SignError> {
    // The kernel selects from the balance in its own state, so the notes being
    // spent have to be pushed in. Fetching them independently would give the
    // kernel a second view of the chain and a plan it cannot reproduce.
    let balance = v1::BalanceUpdate {
        height: request.chain_state.height.clone(),
        block_id: request.chain_state.block_id.clone(),
        notes: v1::note::Balance(request.spent_notes.clone()),
    };
    poke_kernel(app, update_balance_poke(&balance), timeout).await?;

    let poke = create_tx_poke(request, sign_keys)?;
    let effects = poke_kernel(app, poke, timeout).await?;

    let jam = written_transaction(&effects).ok_or_else(|| {
        // The kernel's only channel for saying *why* is a `%markdown` effect
        // meant for a human reading a terminal. Forwarding it verbatim is ugly
        // but it is the difference between a debuggable failure and a shrug.
        SignError::Declined(format!(
            "the wallet kernel built no transaction. It said: {}",
            kernel_explanation(&effects)
        ))
    })?;
    let signed = decode_transaction(&jam)?;

    // `validate_signed` catches a divergence regardless, two layers up, as an
    // opaque `SignerMismatch`. Checking here costs nothing and names the actual
    // problem: the kernel re-planned.
    ensure_input_parity(request, &signed)?;
    Ok(signed)
}

/// Fails when the kernel spent a different set of notes than was named.
///
/// A mismatch means the kernel ignored the explicit `names` list and ran its
/// own selector, which also means its fee is its own — so the diagnosis is
/// "planner parity", not "bad signature".
fn ensure_input_parity(request: &SignRequest, signed: &v1::RawTx) -> Result<(), SignError> {
    let mut requested: Vec<_> = request
        .plan
        .assembled
        .inputs
        .iter()
        .map(|input| name_key(&input.note.name))
        .collect();
    let mut actual: Vec<_> = signed
        .spends
        .0
        .iter()
        .map(|(name, _)| name_key(name))
        .collect();
    requested.sort_unstable();
    actual.sort_unstable();

    if requested != actual {
        return Err(SignError::Declined(format!(
            "planner parity mismatch: the driver named {} input note(s) but the wallet kernel \
             spent {}, so its fee and change are its own rather than the driver's",
            requested.len(),
            actual.len()
        )));
    }
    Ok(())
}

fn name_key(name: &Name) -> ([u64; 5], [u64; 5]) {
    (name.first.to_array(), name.last.to_array())
}

// ---------------------------------------------------------------------------
// Poke encoding
// ---------------------------------------------------------------------------

/// Builds the `[%create-tx ..]` cause pinning the kernel to `request.plan`.
///
/// The cause is the 10-tuple `create-tx-cause` from
/// `hoon/apps/wallet/lib/types.hoon`:
///
/// ```text
/// [names orders fee allow-low-fee sign-keys refund-pkh
///  include-data save-raw-tx selection-strategy multisig]
/// ```
fn create_tx_poke(request: &SignRequest, sign_keys: &[(u64, bool)]) -> Result<NounSlab, SignError> {
    let plan = &request.plan;
    let mut slab: NounSlab = NounSlab::new();

    // `names` — the whole mechanism. An explicit list leaves the kernel's
    // selector exactly one legal answer.
    let names = plan.assembled.inputs.iter().rev().fold(D(0), |acc, input| {
        let first = make_tas(&mut slab, &input.note.name.first.to_base58()).as_noun();
        let last = make_tas(&mut slab, &input.note.name.last.to_base58()).as_noun();
        let pair = T(&mut slab, &[first, last]);
        Cell::new(&mut slab, pair, acc).as_noun()
    });

    // `orders` — *every* planned output, change included, as `%lock-root`. See
    // the module docs: this is what drives the kernel's own refund to zero.
    let orders = plan
        .assembled
        .outputs
        .iter()
        .rev()
        .fold(D(0), |acc, output| {
            let tag = make_tas(&mut slab, "lock-root").as_noun();
            let root = output.lock_root.to_noun(&mut slab);
            let gift = output.amount.to_noun(&mut slab);
            let order = T(&mut slab, &[tag, root, gift]);
            Cell::new(&mut slab, order, acc).as_noun()
        });

    let fee = plan.assembled.fee.to_noun(&mut slab);
    // `allow-low-fee` stays false. The driver's fee is planner-computed; if the
    // kernel thinks it is too low, that is a parity failure worth hearing about
    // rather than suppressing.
    let allow_low_fee = false.to_noun(&mut slab);
    let sign_keys_noun = if sign_keys.is_empty() {
        D(0)
    } else {
        Some(sign_keys.to_vec()).to_noun(&mut slab)
    };
    // `refund-pkh` is `~`: the orders above already account for every nick, so
    // the kernel has no change to place.
    let refund = D(0);
    // Must match `PlanRequest::include_data` in `build.rs`. Disagreeing changes
    // the word count, which changes the fee, which fails parity.
    let include_data = false.to_noun(&mut slab);
    // No debug jams. The transaction comes back through the `%file %write`
    // effect and is decoded in memory.
    let save_raw_tx = false.to_noun(&mut slab);
    // Irrelevant under an explicit `names` list, but the field is not optional.
    let selection = make_tas(&mut slab, "asc").as_noun();
    let multisig = multisig_noun(&mut slab, request)?;

    let cause = T(
        &mut slab,
        &[
            names, orders, fee, allow_low_fee, sign_keys_noun, refund, include_data, save_raw_tx,
            selection, multisig,
        ],
    );
    let full = command(&mut slab, "create-tx", &[cause]);
    slab.set_root(full);
    Ok(slab)
}

/// Builds the `multisig` field: the threshold and participants of an m-of-n
/// input lock.
///
/// A multisig note's note-data omits its lock, so the kernel cannot recover it
/// from the note alone and has to be handed the participants to rebuild it
/// from. A 1-of-1 lock needs none of this, and passing it anyway would make the
/// kernel reconstruct a lock it can already derive.
///
/// Only one such lock is supported per transaction, because the cause has room
/// for exactly one and every input is built against it.
fn multisig_noun(slab: &mut NounSlab, request: &SignRequest) -> Result<Noun, SignError> {
    let multisig: Vec<_> = request
        .plan
        .spend_conditions
        .iter()
        .filter_map(|condition| condition.required_pkh_policy())
        .filter(|policy| policy.threshold > 1 || policy.hashes.len() > 1)
        .collect();

    let policy =
        match multisig.as_slice() {
            [] => return Ok(D(0)),
            [only] => only,
            _ => return Err(SignError::Declined(
                "this transaction spends notes under more than one multisig lock, and the wallet \
                 kernel can rebuild only one input lock per transaction; split the intent"
                    .into(),
            )),
        };

    let participants = policy.hashes.iter().rev().fold(D(0), |acc, hash| {
        let participant = make_tas(slab, &hash.to_base58()).as_noun();
        Cell::new(slab, participant, acc).as_noun()
    });
    let threshold = (policy.threshold as u64).to_noun(slab);
    let payload = T(slab, &[threshold, participants]);
    Ok(T(slab, &[D(0), payload]))
}

fn update_balance_poke(balance: &v1::BalanceUpdate) -> NounSlab {
    let mut slab: NounSlab = NounSlab::new();
    // Double-wrapped to match the kernel's `(unit (unit balance-update))`.
    let wrapped = Some(Some(balance.clone())).to_noun(&mut slab);
    let full = command(&mut slab, "update-balance-grpc", &[wrapped]);
    slab.set_root(full);
    slab
}

fn fakenet_poke(constants: &BlockchainConstants) -> NounSlab {
    let mut slab: NounSlab = NounSlab::new();
    let noun = constants.to_noun(&mut slab);
    let full = command(&mut slab, "fakenet", &[noun]);
    slab.set_root(full);
    slab
}

/// Wraps arguments into the `[%verb args]` cause shape every wallet poke uses.
fn command(slab: &mut NounSlab, verb: &str, args: &[Noun]) -> Noun {
    let head = make_tas(slab, verb).as_noun();
    let tail = match args.len() {
        0 => D(0),
        1 => args[0],
        _ => T(slab, args),
    };
    T(slab, &[head, tail])
}

fn byts_noun(slab: &mut NounSlab, bytes: &[u8]) -> Noun {
    Byts::new(bytes.to_vec()).into_noun(slab)
}

// ---------------------------------------------------------------------------
// Effect decoding
// ---------------------------------------------------------------------------

/// Extracts the jammed transaction from a `[%file %write path contents]`
/// effect, without writing anything.
///
/// The kernel also emits `%markdown`, and emits `%exit` on the failure path;
/// both are ignored. Nothing here forwards `%exit` anywhere, which is what lets
/// the kernel survive more than one signature.
fn written_transaction(effects: &[NounSlab]) -> Option<Bytes> {
    for effect in effects {
        let space = effect.noun_space();
        let noun = unsafe { effect.root() };
        let Ok(cell) = noun.in_space(&space).as_cell() else {
            continue;
        };
        let Ok(tag) = String::from_noun(&cell.head().noun(), &space) else {
            continue;
        };
        if tag != "file" {
            continue;
        }
        let Ok(body) = cell.tail().as_cell() else {
            continue;
        };
        let Ok(operation) = String::from_noun(&body.head().noun(), &space) else {
            continue;
        };
        if operation != "write" {
            continue;
        }
        if let Ok((_path, contents)) = <(String, Bytes)>::from_noun(&body.tail().noun(), &space) {
            return Some(contents);
        }
    }
    None
}

/// Markers that identify a `%markdown` effect carrying key material.
///
/// The wallet kernel answers `keygen` and the `import-*` commands with a
/// human-facing report containing the seed phrase and the extended private key
/// in plaintext. Nothing here should ever forward one of those.
const SECRET_MARKERS: [&str; 4] = ["Seed Phrase", "Extended Private Key", "zprv", "Master Key"];

/// Collects whatever the kernel said in `%markdown` effects.
///
/// `## Poke failed` in particular means the kernel's `soft` rejected the cause
/// outright — the built kernel image and the cause this module encodes have
/// drifted apart — which is worth being able to recognise on sight.
///
/// # Why this filters
///
/// The string this returns ends up inside a [`SignError`], which the driver
/// turns into a `RejectReason`, which it journals to disk and pokes back to the
/// kernel as a `%tx-rejected` cause. So this is a pipe from kernel output to
/// durable storage and to a log, and the wallet kernel's `%markdown` channel is
/// also how it prints seed phrases.
///
/// Today only the `create-tx` response reaches here, and that response carries
/// no key material. That is a fact about the current call graph, not a
/// property of this function, and it is exactly the kind of fact that stops
/// being true quietly. Rather than rely on it, anything bearing a key-material
/// marker is dropped outright — the whole point of this crate's design is that
/// key material never reaches a journal or a log.
fn kernel_explanation(effects: &[NounSlab]) -> String {
    let mut redacted = false;
    let messages: Vec<String> = effects
        .iter()
        .filter_map(|effect| {
            let space = effect.noun_space();
            let noun = unsafe { effect.root() };
            let cell = noun.in_space(&space).as_cell().ok()?;
            if String::from_noun(&cell.head().noun(), &space).ok()? != "markdown" {
                return None;
            }
            let message = String::from_noun(&cell.tail().noun(), &space).ok()?;
            if SECRET_MARKERS.iter().any(|marker| message.contains(marker)) {
                redacted = true;
                return None;
            }
            Some(message)
        })
        .collect();

    match (messages.is_empty(), redacted) {
        (true, true) => "<redacted: the kernel's reply carried key material>".into(),
        (true, false) => "nothing at all — it emitted no diagnostic effect".into(),
        _ => messages.join(" / ").replace('\n', " "),
    }
}

/// Cues a saved `transaction-1` and reassembles it into a [`v1::RawTx`].
///
/// The envelope is `[%1 name spends metadata witness-data]`: the signatures
/// live in `witness-data`, keyed by note name, rather than inside the spends.
/// Reattaching them is what turns the saved form back into a raw transaction.
///
/// The transaction id is recomputed from the reassembled contents rather than
/// read from the envelope's `name` field, so the id this returns is the one the
/// network will derive. [`crate::sign::validate_signed`] checks it again.
fn decode_transaction(jam: &Bytes) -> Result<v1::RawTx, SignError> {
    let undecodable = |message: String| SignError::Undecodable(message);

    let mut slab: NounSlab = NounSlab::new();
    let root = slab
        .cue_into(jam.clone())
        .map_err(|err| undecodable(format!("saved transaction did not cue: {err}")))?;
    let space = slab.noun_space();

    let cell = root
        .in_space(&space)
        .as_cell()
        .map_err(|err| undecodable(format!("saved transaction root is not a cell: {err}")))?;
    let version = <u64 as NounDecode>::from_noun(&cell.head().noun(), &space)
        .map_err(|err| undecodable(format!("saved transaction version: {err}")))?;
    if version != 1 {
        return Err(undecodable(format!(
            "expected a version 1 saved transaction, got {version}"
        )));
    }

    let after_name = cell
        .tail()
        .as_cell()
        .map_err(|err| undecodable(format!("saved transaction has no name: {err}")))?;
    let after_spends = after_name
        .tail()
        .as_cell()
        .map_err(|err| undecodable(format!("saved transaction has no spends: {err}")))?;
    let mut spends = v1::Spends::from_noun(&after_spends.head().noun(), &space)
        .map_err(|err| undecodable(format!("saved transaction spends: {err}")))?;

    let after_metadata = after_spends
        .tail()
        .as_cell()
        .map_err(|err| undecodable(format!("saved transaction has no witness-data: {err}")))?;
    let witness_data = after_metadata
        .tail()
        .as_cell()
        .map_err(|err| undecodable(format!("witness-data is not a cell: {err}")))?;
    let witness_tag = <u64 as NounDecode>::from_noun(&witness_data.head().noun(), &space)
        .map_err(|err| undecodable(format!("witness-data tag: {err}")))?;

    match witness_tag {
        0 => {
            let signatures =
                ZMap::<Name, Signature>::from_noun(&witness_data.tail().noun(), &space)
                    .map_err(|err| undecodable(format!("legacy witness-data: {err}")))?;
            for (name, signature) in signatures.into_entries() {
                let Some((_, v1::Spend::Legacy(spend0))) = spends
                    .0
                    .iter_mut()
                    .find(|(candidate, _)| *candidate == name)
                else {
                    return Err(undecodable(format!(
                        "witness-data names a spend the transaction does not have: {}",
                        name.first.to_base58()
                    )));
                };
                spend0.signature = signature;
            }
        }
        1 => {
            let witnesses =
                ZMap::<Name, v1::Witness>::from_noun(&witness_data.tail().noun(), &space)
                    .map_err(|err| undecodable(format!("v1 witness-data: {err}")))?;
            for (name, witness) in witnesses.into_entries() {
                let Some((_, v1::Spend::Witness(spend1))) = spends
                    .0
                    .iter_mut()
                    .find(|(candidate, _)| *candidate == name)
                else {
                    return Err(undecodable(format!(
                        "witness-data names a spend the transaction does not have: {}",
                        name.first.to_base58()
                    )));
                };
                spend1.witness = witness;
            }
        }
        other => return Err(undecodable(format!("unsupported witness-data tag {other}"))),
    }

    let mut tx = v1::RawTx {
        version: Version::V1,
        id: Hash([Belt(0); 5]),
        spends,
    };
    tx.id = tx
        .compute_id()
        .map_err(|err| undecodable(format!("reassembled transaction id: {err}")))?;
    Ok(tx)
}

// ---------------------------------------------------------------------------
// Kernel plumbing
// ---------------------------------------------------------------------------

/// A poke issued during construction, unbounded. See `KernelSignerConfig::timeout`.
async fn setup_poke(app: &mut NockApp, poke: NounSlab) -> Result<Vec<NounSlab>, SignError> {
    app.poke(wire(), poke)
        .await
        .map_err(|err| classify(err, "setup poke"))
}

async fn poke_kernel(
    app: &mut NockApp,
    poke: NounSlab,
    timeout: Duration,
) -> Result<Vec<NounSlab>, SignError> {
    app.poke_timeout(wire(), poke, timeout)
        .await
        .map_err(|err| classify(err, "poke"))
}

/// Maps a kernel failure onto the right terminal/non-terminal [`SignError`].
///
/// This split is load-bearing: `SignError::is_terminal` decides whether the
/// driver reports a terminal `Rejected` (safe to roll back against) or a
/// retryable `Failed` (status unknown). Getting it backwards either strands a
/// recoverable intent or invites a second transaction against the same notes.
///
/// The rule is *whether a retry could ever succeed*. A timeout or a dead
/// channel says nothing about the request, so it is non-terminal. A Hoon crash
/// is deterministic: the same poke will crash again.
fn classify(err: NockAppError, context: &str) -> SignError {
    match err {
        // Both spellings matter. `poke_timeout` reports a lapsed deadline as
        // `CrownError::Timeout` rather than `NockAppError::Timeout`, and
        // missing that variant silently turns every hung kernel into a
        // terminal rejection — the one classification error this whole split
        // exists to prevent.
        NockAppError::Timeout | NockAppError::CrownError(CrownError::Timeout) => {
            SignError::Unavailable(format!(
                "the wallet kernel did not answer within the configured timeout ({context})"
            ))
        }
        NockAppError::ChannelClosedError
        | NockAppError::MPSCSendError(_)
        | NockAppError::OneShotRecvError(_)
        | NockAppError::JoinError(_)
        | NockAppError::IoError(_) => SignError::Unavailable(format!(
            "the wallet kernel is not reachable ({context}): {err}"
        )),
        other => SignError::Declined(format!("the wallet kernel refused the {context}: {other}")),
    }
}

#[cfg(test)]
mod tests;
