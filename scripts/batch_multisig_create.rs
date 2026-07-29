#!/usr/bin/env rust-script
//! ```cargo
//! [package]
//! edition = "2021"
//! ```
//!
//! batch_multisig_create.rs
//! ========================
//!
//! Repeatedly create multisig transactions, draining a notes CSV until it is
//! exhausted (or the remaining notes can no longer fund another payment).
//!
//! Each iteration shells out to `nockchain-wallet create-multisig-tx --notes-csv
//! <CSV> ...`. That command:
//!   * auto-selects candidate notes *from the CSV* (no network sync — offline),
//!   * writes the resulting transaction to `./txs/<name>.tx`, and
//!   * removes the notes it actually spent from the CSV.
//!
//! So we just loop until the CSV has no data rows left, or until an iteration
//! makes no progress (the planner could not fund another tx from what remains).
//!
//! The CSV is MUTATED IN PLACE by the wallet. A timestamped `.bak` copy is made
//! before the first iteration unless `--no-backup` is given.
//!
//! Usage
//! -----
//!   scripts/batch_multisig_create.rs \
//!     --notes-csv notes-multisig-<root>.csv \
//!     --threshold 2 \
//!     --participants <pkh1>,<pkh2>,<pkh3> \
//!     --recipient '{"kind":"p2pkh","address":"<dest-b58>","amount":1000000}' \
//!     [--fee 65536] \
//!     [--sign-key 0:false] \
//!     [--txs-dir txs] \
//!     [--max-txs N] \
//!     [--dry-run] [--no-backup] \
//!     -- --data-dir ./test_run_data/wallet --fakenet   # passthrough wallet globals
//!
//! Everything after a literal `--` is passed verbatim to `nockchain-wallet`
//! BEFORE the subcommand (that is where wallet global flags such as --data-dir,
//! --fakenet, --client, --private-grpc-server-port live).
//!
//! The wallet binary is resolved from $NOCKCHAIN_WALLET, else `nockchain-wallet`
//! on PATH. The notes CSV must already correspond to a synced wallet (generate
//! it with `nockchain-wallet ... list-notes-by-multisig-csv <first-name>`).

use std::collections::BTreeSet;
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

    if let Err(e) = run(&cfg) {
        eprintln!("error: {e}");
        exit(1);
    }
}

const USAGE: &str = "\
Usage: batch_multisig_create.rs --notes-csv <CSV> --threshold <M> \\
         --participants <PKH,...> --recipient <SPEC> [--recipient <SPEC> ...] \\
         [--fee <NICKS>] [--sign-key <INDEX:HARDENED> ...] [--allow-low-fee] \\
         [--txs-dir <DIR>] [--max-txs <N>] [--dry-run] [--no-backup] \\
         [-- <wallet global args...>]";

struct Config {
    wallet: String,
    notes_csv: PathBuf,
    threshold: String,
    participants: String,
    recipients: Vec<String>,
    fee: Option<String>,
    sign_keys: Vec<String>,
    allow_low_fee: bool,
    refund_pkh: Option<String>,
    txs_dir: PathBuf,
    max_txs: Option<usize>,
    dry_run: bool,
    no_backup: bool,
    passthrough: Vec<String>,
}

impl Config {
    fn parse(args: Vec<String>) -> Result<Config, String> {
        let mut notes_csv: Option<PathBuf> = None;
        let mut threshold: Option<String> = None;
        let mut participants: Option<String> = None;
        let mut recipients: Vec<String> = Vec::new();
        let mut fee: Option<String> = None;
        let mut sign_keys: Vec<String> = Vec::new();
        let mut allow_low_fee = false;
        let mut refund_pkh: Option<String> = None;
        let mut txs_dir = PathBuf::from("txs");
        let mut max_txs: Option<usize> = None;
        let mut dry_run = false;
        let mut no_backup = false;
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
                "--notes-csv" => notes_csv = Some(PathBuf::from(next("--notes-csv")?)),
                "--threshold" | "-t" => threshold = Some(next("--threshold")?),
                "--participants" => participants = Some(next("--participants")?),
                "--recipient" => recipients.push(next("--recipient")?),
                "--fee" => fee = Some(next("--fee")?),
                "--sign-key" => sign_keys.push(next("--sign-key")?),
                "--allow-low-fee" => allow_low_fee = true,
                "--refund-pkh" => refund_pkh = Some(next("--refund-pkh")?),
                "--txs-dir" => txs_dir = PathBuf::from(next("--txs-dir")?),
                "--max-txs" => {
                    max_txs = Some(
                        next("--max-txs")?
                            .parse()
                            .map_err(|_| "--max-txs must be a non-negative integer".to_string())?,
                    )
                }
                "--dry-run" => dry_run = true,
                "--no-backup" => no_backup = true,
                other => return Err(format!("unknown argument: {other}")),
            }
        }

        let notes_csv = notes_csv.ok_or("--notes-csv is required")?;
        let threshold = threshold.ok_or("--threshold is required")?;
        let participants = participants.ok_or("--participants is required")?;
        if recipients.is_empty() {
            return Err("at least one --recipient is required".to_string());
        }

        Ok(Config {
            wallet: std::env::var("NOCKCHAIN_WALLET").unwrap_or_else(|_| "nockchain-wallet".into()),
            notes_csv,
            threshold,
            participants,
            recipients,
            fee,
            sign_keys,
            allow_low_fee,
            refund_pkh,
            txs_dir,
            max_txs,
            dry_run,
            no_backup,
            passthrough,
        })
    }
}

fn run(cfg: &Config) -> Result<(), String> {
    if !cfg.notes_csv.exists() {
        return Err(format!("notes CSV not found: {}", cfg.notes_csv.display()));
    }

    let start_rows = count_data_rows(&cfg.notes_csv)?;
    println!(
        "batch-multisig-create: draining {} ({} note row(s)) via {}-of-N multisig",
        cfg.notes_csv.display(),
        start_rows,
        cfg.threshold,
    );
    if start_rows == 0 {
        println!("notes CSV already exhausted — nothing to do.");
        return Ok(());
    }

    if cfg.dry_run {
        println!("[dry-run] would invoke (per iteration, until CSV exhausted):");
        print_cmd(&cfg.wallet, &build_args(cfg));
        println!("[dry-run] CSV would be drained from {start_rows} row(s); no commands executed.");
        return Ok(());
    }

    if !cfg.no_backup {
        let bak = backup_path(&cfg.notes_csv);
        fs::copy(&cfg.notes_csv, &bak)
            .map_err(|e| format!("failed to back up notes CSV to {}: {e}", bak.display()))?;
        println!("backed up notes CSV -> {}", bak.display());
    }

    fs::create_dir_all(&cfg.txs_dir)
        .map_err(|e| format!("failed to create txs dir {}: {e}", cfg.txs_dir.display()))?;

    let mut created: Vec<String> = Vec::new();
    let mut iteration = 0usize;

    loop {
        let rows_before = count_data_rows(&cfg.notes_csv)?;
        if rows_before == 0 {
            println!("\nnotes CSV exhausted — all notes spent.");
            break;
        }
        if let Some(max) = cfg.max_txs {
            if iteration >= max {
                println!("\nreached --max-txs={max}; {rows_before} note row(s) still remain.");
                break;
            }
        }

        iteration += 1;
        println!(
            "\n--- iteration {iteration} | {rows_before} note row(s) remaining ---"
        );

        let txs_before = list_tx_files(&cfg.txs_dir);
        let args = build_args(cfg);
        print_cmd(&cfg.wallet, &args);

        let status = Command::new(&cfg.wallet)
            .args(&args)
            .status()
            .map_err(|e| format!("failed to launch wallet binary '{}': {e}", cfg.wallet))?;

        let rows_after = count_data_rows(&cfg.notes_csv)?;
        let txs_after = list_tx_files(&cfg.txs_dir);
        let new_tx: Vec<String> = txs_after.difference(&txs_before).cloned().collect();

        if !status.success() {
            println!(
                "wallet exited with {} and consumed no notes; stopping.",
                status
            );
            break;
        }

        // Success exit but the planner could not fund a tx from what remains:
        // no notes were pruned and no tx file appeared. Stop to avoid looping
        // forever on a CSV that can never make further progress.
        if rows_after >= rows_before && new_tx.is_empty() {
            println!(
                "no notes were spent and no transaction was written \
                 (remaining notes can't fund another payment at this amount/fee); stopping."
            );
            break;
        }

        for tx in &new_tx {
            println!("  created: {}", cfg.txs_dir.join(tx).display());
            created.push(tx.clone());
        }
        println!("  notes remaining: {rows_after} (was {rows_before})");
    }

    println!(
        "\nDone. {} transaction(s) created in {}; {} note row(s) left in {}.",
        created.len(),
        cfg.txs_dir.display(),
        count_data_rows(&cfg.notes_csv).unwrap_or(0),
        cfg.notes_csv.display(),
    );
    if !created.is_empty() {
        println!("Next: sign them with scripts/batch_multisig_sign.rs --tx-dir {}", cfg.txs_dir.display());
    }
    Ok(())
}

/// Build the full `nockchain-wallet` argv: passthrough globals, then the
/// `create-multisig-tx` subcommand and its flags.
fn build_args(cfg: &Config) -> Vec<String> {
    let mut a: Vec<String> = Vec::new();
    a.extend(cfg.passthrough.iter().cloned());
    a.push("create-multisig-tx".into());
    a.push("--threshold".into());
    a.push(cfg.threshold.clone());
    a.push("--participants".into());
    a.push(cfg.participants.clone());
    a.push("--notes-csv".into());
    a.push(cfg.notes_csv.to_string_lossy().into_owned());
    for r in &cfg.recipients {
        a.push("--recipient".into());
        a.push(r.clone());
    }
    if let Some(fee) = &cfg.fee {
        a.push("--fee".into());
        a.push(fee.clone());
    }
    if cfg.allow_low_fee {
        a.push("--allow-low-fee".into());
    }
    if let Some(refund) = &cfg.refund_pkh {
        a.push("--refund-pkh".into());
        a.push(refund.clone());
    }
    for k in &cfg.sign_keys {
        a.push("--sign-key".into());
        a.push(k.clone());
    }
    a
}

fn print_cmd(bin: &str, args: &[String]) {
    let rendered: Vec<String> = args
        .iter()
        .map(|a| {
            if a.chars().any(|c| c.is_whitespace() || c == '{' || c == '"') {
                format!("'{a}'")
            } else {
                a.clone()
            }
        })
        .collect();
    println!("  $ {bin} {}", rendered.join(" "));
}

/// Count note data rows in a notes CSV: non-empty lines that are neither the
/// header (`version,...`) nor a comment, carrying at least the three required
/// columns (version, name_first, name_last). Mirrors what the wallet's own
/// parser keeps, so it tracks the in-place pruning the wallet performs.
fn count_data_rows(path: &Path) -> Result<usize, String> {
    let text = fs::read_to_string(path)
        .map_err(|e| format!("failed to read {}: {e}", path.display()))?;
    let mut n = 0usize;
    for line in text.lines() {
        let line = line.trim_matches(|c: char| c == '\0' || c.is_whitespace());
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        if line.starts_with("version,") || line == "version" {
            continue;
        }
        if line.split(',').count() >= 3 {
            n += 1;
        }
    }
    Ok(n)
}

fn list_tx_files(dir: &Path) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    if let Ok(entries) = fs::read_dir(dir) {
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.ends_with(".tx") {
                set.insert(name);
            }
        }
    }
    set
}

fn backup_path(csv: &Path) -> PathBuf {
    let mut name = csv.file_name().unwrap_or_default().to_os_string();
    name.push(".bak");
    csv.with_file_name(name)
}
