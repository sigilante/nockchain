#!/usr/bin/env rust-script
//! ```cargo
//! [package]
//! edition = "2021"
//! ```
//!
//! batch_multisig_sign.rs
//! ======================
//!
//! Sign every transaction file in a folder, moving each successfully-signed tx
//! into a `done/` directory so the source folder behaves like a work queue.
//!
//! For each `*.tx` in `--tx-dir` (sorted) this shells out to:
//!     nockchain-wallet sign-multisig-tx <file> [--sign-keys <INDEX:HARDENED,...>]
//!
//! `sign-multisig-tx` is OFFLINE: it reads the tx (jam), adds this signer's
//! signatures in place, and writes the tx back to the same path. On success we
//! move the file into `--done-dir`. Files that fail to sign are left in place
//! and reported at the end (non-zero exit if any failed).
//!
//! NOTE: "done" means *this signer has signed*. For an m-of-n multisig that
//! still needs more signatures, route the files in `--done-dir` to the next
//! signer (point their `--tx-dir` at it). Once the threshold is met, broadcast
//! with `nockchain-wallet send-tx <file>` — or pass `--send` here.
//!
//! With `--send` (ONLINE), each tx is broadcast right after signing:
//!   * if `send-tx` validates and submits, the file moves to `--sent-dir`;
//!   * if it does not (typically the m-of-n threshold is not met yet), the file
//!     stays signed and moves to `--done-dir` to await more signatures. This is
//!     not treated as a hard error — only a failure to *sign* is.
//!
//! Usage
//! -----
//!   scripts/batch_multisig_sign.rs \
//!     --tx-dir txs \
//!     [--done-dir txs/signed] [--sent-dir txs/sent] \
//!     [--sign-keys 1:true,2:false] [--send] \
//!     [--dry-run] [--continue-on-error] \
//!     -- --data-dir ./test_run_data/wallet --fakenet   # passthrough wallet globals
//!
//! Everything after a literal `--` is passed verbatim to `nockchain-wallet`
//! BEFORE the subcommand (wallet global flags: --data-dir, --fakenet, and for
//! `--send` the client/grpc flags: --client, --public-grpc-server-addr, etc.).
//! If `--sign-keys` is omitted the wallet signs with its master key.
//!
//! The wallet binary is resolved from $NOCKCHAIN_WALLET, else `nockchain-wallet`.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::{exit, Command};

fn main() {
    let cfg = match Config::parse(std::env::args().skip(1).collect()) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("error: {e}\n");
            eprintln!("{USAGE}");
            exit(2);
        }
    };
    match run(&cfg) {
        Ok(0) => {}
        Ok(failed) => {
            eprintln!("\n{failed} transaction(s) failed to sign (left in {}).", cfg.tx_dir.display());
            exit(1);
        }
        Err(e) => {
            eprintln!("error: {e}");
            exit(1);
        }
    }
}

const USAGE: &str = "\
Usage: batch_multisig_sign.rs --tx-dir <DIR> [--done-dir <DIR>] [--sent-dir <DIR>] \\
         [--sign-keys <INDEX:HARDENED,...>] [--send] [--dry-run] [--continue-on-error] \\
         [-- <wallet global args...>]";

struct Config {
    wallet: String,
    tx_dir: PathBuf,
    done_dir: PathBuf,
    sent_dir: PathBuf,
    sign_keys: Option<String>,
    send: bool,
    dry_run: bool,
    continue_on_error: bool,
    passthrough: Vec<String>,
}

impl Config {
    fn parse(args: Vec<String>) -> Result<Config, String> {
        let mut tx_dir: Option<PathBuf> = None;
        let mut done_dir: Option<PathBuf> = None;
        let mut sent_dir: Option<PathBuf> = None;
        let mut sign_keys: Option<String> = None;
        let mut send = false;
        let mut dry_run = false;
        let mut continue_on_error = false;
        let mut passthrough: Vec<String> = Vec::new();

        let mut it = args.into_iter();
        while let Some(arg) = it.next() {
            let mut next = |flag: &str| -> Result<String, String> {
                it.next().ok_or_else(|| format!("{flag} requires a value"))
            };
            match arg.as_str() {
                "--" => {
                    passthrough.extend(it.by_ref());
                    break;
                }
                "-h" | "--help" => {
                    println!("{USAGE}");
                    exit(0);
                }
                "--wallet" => std::env::set_var("NOCKCHAIN_WALLET", next("--wallet")?),
                "--tx-dir" => tx_dir = Some(PathBuf::from(next("--tx-dir")?)),
                "--done-dir" => done_dir = Some(PathBuf::from(next("--done-dir")?)),
                "--sent-dir" => sent_dir = Some(PathBuf::from(next("--sent-dir")?)),
                "--sign-keys" => sign_keys = Some(next("--sign-keys")?),
                "--send" => send = true,
                "--dry-run" => dry_run = true,
                "--continue-on-error" => continue_on_error = true,
                other => return Err(format!("unknown argument: {other}")),
            }
        }

        let tx_dir = tx_dir.ok_or("--tx-dir is required")?;
        let done_dir = done_dir.unwrap_or_else(|| tx_dir.join("signed"));
        let sent_dir = sent_dir.unwrap_or_else(|| tx_dir.join("sent"));

        Ok(Config {
            wallet: std::env::var("NOCKCHAIN_WALLET").unwrap_or_else(|_| "nockchain-wallet".into()),
            tx_dir,
            done_dir,
            sent_dir,
            sign_keys,
            send,
            dry_run,
            continue_on_error,
            passthrough,
        })
    }
}

fn run(cfg: &Config) -> Result<usize, String> {
    if !cfg.tx_dir.is_dir() {
        return Err(format!("tx dir not found: {}", cfg.tx_dir.display()));
    }

    let exclude = [cfg.done_dir.as_path(), cfg.sent_dir.as_path()];
    let txs = list_tx_files(&cfg.tx_dir, &exclude)?;
    println!(
        "batch-multisig-sign: {} transaction(s) in {} -> signed:{}{}",
        txs.len(),
        cfg.tx_dir.display(),
        cfg.done_dir.display(),
        if cfg.send {
            format!(" sent:{}", cfg.sent_dir.display())
        } else {
            String::new()
        },
    );
    if txs.is_empty() {
        println!("nothing to sign.");
        return Ok(0);
    }

    if cfg.dry_run {
        println!("[dry-run] would sign{} each of:", if cfg.send { " (then send)" } else { "" });
        for tx in &txs {
            print_cmd(&cfg.wallet, &build_sign_args(cfg, tx));
            if cfg.send {
                print_cmd(&cfg.wallet, &build_send_args(cfg, tx));
            }
        }
        println!("[dry-run] signed -> {}", cfg.done_dir.display());
        if cfg.send {
            println!("[dry-run] sent (threshold met) -> {}", cfg.sent_dir.display());
        }
        return Ok(0);
    }

    fs::create_dir_all(&cfg.done_dir)
        .map_err(|e| format!("failed to create done dir {}: {e}", cfg.done_dir.display()))?;
    if cfg.send {
        fs::create_dir_all(&cfg.sent_dir)
            .map_err(|e| format!("failed to create sent dir {}: {e}", cfg.sent_dir.display()))?;
    }

    let mut signed = 0usize;
    let mut sent = 0usize;
    let mut failed = 0usize;

    for tx in &txs {
        println!("\n--- signing {} ---", tx.display());
        let sign_args = build_sign_args(cfg, tx);
        print_cmd(&cfg.wallet, &sign_args);

        let status = Command::new(&cfg.wallet)
            .args(&sign_args)
            .status()
            .map_err(|e| format!("failed to launch wallet binary '{}': {e}", cfg.wallet))?;

        if !status.success() {
            eprintln!("  FAILED to sign ({status}); leaving {} in place.", tx.display());
            failed += 1;
            if cfg.continue_on_error {
                continue;
            }
            return Err(format!(
                "signing failed for {} — stopping (pass --continue-on-error to skip and continue)",
                tx.display()
            ));
        }

        // Optionally broadcast. A send that does not validate (typically the
        // m-of-n threshold is not met yet) is expected in a multi-party flow:
        // keep the signed tx in done/ for the next signer rather than erroring.
        if cfg.send {
            let send_args = build_send_args(cfg, tx);
            print_cmd(&cfg.wallet, &send_args);
            let send_status = Command::new(&cfg.wallet)
                .args(&send_args)
                .status()
                .map_err(|e| format!("failed to launch wallet binary '{}': {e}", cfg.wallet))?;
            if send_status.success() {
                let dest = move_into(tx, &cfg.sent_dir)?;
                println!("  signed + sent -> {}", dest.display());
                sent += 1;
                continue;
            }
            println!(
                "  signed but not broadcast ({send_status}) — likely below threshold; \
                 moving to {} to await more signatures.",
                cfg.done_dir.display()
            );
        }

        let dest = move_into(tx, &cfg.done_dir)?;
        println!("  signed -> {}", dest.display());
        signed += 1;
    }

    if cfg.send {
        println!("\nDone. sent {sent}, signed-awaiting-threshold {signed}, failed-to-sign {failed}.");
    } else {
        println!("\nDone. signed {signed}, failed {failed}.");
    }
    Ok(failed)
}

fn move_into(file: &Path, dir: &Path) -> Result<PathBuf, String> {
    let dest = dir.join(file.file_name().unwrap());
    fs::rename(file, &dest)
        .map_err(|e| format!("processed {} but failed to move it to {}: {e}", file.display(), dest.display()))?;
    Ok(dest)
}

fn build_sign_args(cfg: &Config, tx: &Path) -> Vec<String> {
    let mut a: Vec<String> = Vec::new();
    a.extend(cfg.passthrough.iter().cloned());
    a.push("sign-multisig-tx".into());
    a.push(tx.to_string_lossy().into_owned());
    if let Some(keys) = &cfg.sign_keys {
        a.push("--sign-keys".into());
        a.push(keys.clone());
    }
    a
}

fn build_send_args(cfg: &Config, tx: &Path) -> Vec<String> {
    let mut a: Vec<String> = Vec::new();
    a.extend(cfg.passthrough.iter().cloned());
    a.push("send-tx".into());
    a.push(tx.to_string_lossy().into_owned());
    a
}

fn print_cmd(bin: &str, args: &[String]) {
    let rendered: Vec<String> = args
        .iter()
        .map(|a| {
            if a.chars().any(|c| c.is_whitespace()) {
                format!("'{a}'")
            } else {
                a.clone()
            }
        })
        .collect();
    println!("  $ {bin} {}", rendered.join(" "));
}

/// All top-level `*.tx` files directly in `tx_dir`, sorted, excluding anything
/// under one of `exclude_dirs` (e.g. done/ or sent/, which may be nested inside
/// `tx_dir`).
fn list_tx_files(tx_dir: &Path, exclude_dirs: &[&Path]) -> Result<Vec<PathBuf>, String> {
    let excl_canon: Vec<PathBuf> = exclude_dirs
        .iter()
        .filter_map(|d| fs::canonicalize(d).ok())
        .collect();
    let mut out = Vec::new();
    let entries = fs::read_dir(tx_dir)
        .map_err(|e| format!("failed to read {}: {e}", tx_dir.display()))?;
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if path.extension().and_then(|e| e.to_str()) != Some("tx") {
            continue;
        }
        // Skip files that live inside an excluded dir (when it == tx_dir).
        if let Ok(pc) = fs::canonicalize(&path) {
            if excl_canon.iter().any(|d| pc.starts_with(d)) {
                continue;
            }
        }
        out.push(path);
    }
    out.sort();
    Ok(out)
}
