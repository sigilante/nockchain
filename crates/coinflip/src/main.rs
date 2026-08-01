//! Runnable narrative of a commit–reveal coinflip.
//!
//! Runs against an in-memory chain (`tx_driver::testing::MockChainSource`), so
//! it needs no node and settles no real money. Every hash, lock root, and
//! first-name it prints is computed with the same code the wallet and the Hoon
//! tx-engine use, so the *cryptography* is real even though the chain is not.
//!
//! ```sh
//! cargo run -p coinflip --bin coinflip-demo
//! ```

use std::sync::Arc;

use coinflip::{GameTerms, Player, Secret, Winner};
use nockchain_math::belt::Belt;
use nockchain_types::tx_engine::common::{BlockHeight, Hash};
use tx_driver::intent::{FeePolicy, IntentId, NoteSelection, Recipient, TxIntent};
use tx_driver::notes::{check_spend_condition, UnlockContext};
use tx_driver::testing::{note_for, MockChainSource, MockSigner};
use tx_driver::{ConfirmPolicy, TxDriver, TxDriverConfig, TxOutcome};

const STAKE: u64 = 1_000_000;
const REFUND_AFTER: u64 = 500;
const NOW: u64 = 100;

fn pkh(seed: u64) -> Hash {
    Hash([Belt(seed + 1), Belt(seed + 2), Belt(seed + 3), Belt(seed + 4), Belt(seed + 5)])
}

fn rule(title: &str) {
    println!("\n\x1b[1m{title}\x1b[0m");
    println!("{}", "-".repeat(title.len()));
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // ---------------------------------------------------------------- commit
    rule("1. Commit");

    // In a real game these come from a CSPRNG and never leave the player's
    // machine until the reveal phase.
    let alice = Player::new(pkh(1), Secret::new([0xA1, 0xA2, 0xA3, 0xA4]));
    let bob = Player::new(pkh(2), Secret::new([0xB1, 0xB2, 0xB3, 0xB5]));

    println!(
        "Alice commits h(a) = {}",
        alice.commit().commitment.to_base58()
    );
    println!(
        "Bob   commits h(b) = {}",
        bob.commit().commitment.to_base58()
    );
    println!(
        "\nBob commits only after seeing Alice's *hash*, never her secret, so he\n\
         cannot steer the result. Each player holds exactly one secret, so\n\
         neither gains anything by revealing second."
    );

    let terms = GameTerms::new(
        alice.commit(),
        bob.commit(),
        STAKE,
        BlockHeight(Belt(REFUND_AFTER)),
    )?;

    // ------------------------------------------------------------------ lock
    rule("2. The lock both players fund");

    let lock_root = terms.lock_root()?;
    println!("branch 0 (settle): Hax{{h(a), h(b)}} AND Pkh{{m=2, {{alice, bob}}}}");
    println!("branch 1 (refund): Tim{{abs.min={REFUND_AFTER}}} AND Pkh{{m=2, {{alice, bob}}}}");
    println!("\nlock root  = {}", lock_root.to_base58());
    println!("first-name = {}", terms.first_name()?.to_base58());
    println!("pot        = {} nicks", terms.pot_nicks());

    // ------------------------------------------------------------------ fund
    rule("3. Funding the pot with tx-driver");

    // Alice's wallet holds one note; she pays her stake into the game lock.
    let alice_lock =
        nockchain_types::tx_engine::v1::tx::SpendCondition::simple_pkh(alice.pkh.clone());
    let chain = MockChainSource::new(NOW, vec![note_for(&alice_lock, 900, 1, 50_000_000)]);
    let journal = tempfile::tempdir()?;
    let driver = TxDriver::new(
        TxDriverConfig {
            journal_dir: journal.path().to_path_buf(),
            dry_run: false,
            confirm: ConfirmPolicy::NoWait,
            coinbase_relative_min: None,
            outcome_buffer: 8,
        },
        Arc::new(chain),
        Arc::new(MockSigner::new(vec![alice.pkh.clone()])),
    )
    .await?;

    // `Recipient::to_tree` is what lets a payer fund a multi-branch lock at
    // all: an output commits only to a lock root, so the payer does not need
    // to understand the structure behind it.
    let funding = TxIntent {
        id: IntentId::from_u128(0xC0_1F_11B_u128),
        from: vec![alice_lock.clone()],
        recipients: vec![Recipient::to_tree(terms.lock(), STAKE)],
        refund_to: None,
        fee: FeePolicy::Auto,
        note_selection: NoteSelection::Auto,
        deadline: None,
    };

    match driver.submit(funding).await? {
        TxOutcome::Submitted { tx_id, .. } | TxOutcome::Confirmed { tx_id, .. } => {
            println!("Alice's stake funded, tx {}", tx_id.to_base58());
        }
        other => {
            println!("funding did not settle: {other:?}");
            return Ok(());
        }
    }
    println!("(Bob funds identically; omitted for brevity.)");

    // ---------------------------------------------------------------- reveal
    rule("4. Reveal");

    println!("Alice reveals a = {:?}", alice.secret.limbs());
    println!("Bob   reveals b = {:?}", bob.secret.limbs());

    let winner = terms.resolve(&alice.secret, &bob.secret)?;
    println!(
        "\nparity(a) XOR parity(b) -> {}",
        match winner {
            Winner::Alice => "0  ->  Alice wins",
            Winner::Bob => "1  ->  Bob wins",
        }
    );
    println!("pot pays {}", terms.payee(winner).to_base58());

    // A forged reveal is refused, so neither player can equivocate.
    let forged = Secret::new([9, 9, 9, 9]);
    match terms.resolve(&forged, &bob.secret) {
        Err(err) => println!("\nAlice tries to substitute a secret: {err}"),
        Ok(_) => println!("\nBUG: a forged reveal was accepted"),
    }

    // ----------------------------------------------------- who can spend now
    rule("5. Which branch is spendable, and by whom");

    let now = BlockHeight(Belt(NOW));
    let origin = BlockHeight(Belt(1));
    let both_secrets = [alice.secret, bob.secret];

    let ctx = |keys: &[Hash], secrets: &[Secret]| {
        let mut ctx = UnlockContext::new().with_signer_pkhs(keys.to_vec());
        for secret in secrets {
            ctx = ctx.with_preimage(
                secret.commitment(),
                secret
                    .limbs()
                    .iter()
                    .flat_map(|v| v.to_le_bytes())
                    .collect(),
            );
        }
        ctx
    };

    let cases: Vec<(&str, UnlockContext)> = vec![
        (
            "alice alone, both secrets",
            ctx(std::slice::from_ref(&alice.pkh), &both_secrets),
        ),
        (
            "bob alone, both secrets",
            ctx(std::slice::from_ref(&bob.pkh), &both_secrets),
        ),
        (
            "both players, only alice's secret",
            ctx(&[alice.pkh.clone(), bob.pkh.clone()], &[alice.secret]),
        ),
        (
            "both players, both secrets",
            ctx(&[alice.pkh.clone(), bob.pkh.clone()], &both_secrets),
        ),
    ];

    for (label, context) in &cases {
        let settle = check_spend_condition(&terms.settle_branch(), context, &now, &origin);
        println!(
            "  settle @{NOW:<6} {label:<34} {}",
            match settle {
                Ok(()) => "SPENDABLE".to_string(),
                Err(reason) => format!("no — {reason}"),
            }
        );
    }

    let cooperative = ctx(&[alice.pkh.clone(), bob.pkh.clone()], &[]);
    for at in [NOW, REFUND_AFTER] {
        let height = BlockHeight(Belt(at));
        let refund = check_spend_condition(&terms.refund_branch(), &cooperative, &height, &origin);
        println!(
            "  refund @{at:<6} {:<34} {}",
            "both players, no secrets",
            match refund {
                Ok(()) => "SPENDABLE".to_string(),
                Err(reason) => format!("no — {reason}"),
            }
        );
    }

    // ----------------------------------------------------------------- caveat
    rule("What this does and does not guarantee");
    println!(
        "The OUTCOME is enforced: unbiased, binding, and neither player can\n\
         equivocate or change it after committing.\n\n\
         The PAYOUT is cooperative. Settlement needs both signatures, so a\n\
         losing player can refuse to sign and the stake returns to both at the\n\
         refund deadline. Cheating is griefable but not profitable: it denies\n\
         the winner their winnings, it does not transfer them to the cheat.\n\n\
         Making the loser pay needs per-player bonds in separate notes. Locks\n\
         here are predicates on WHETHER a note may be spent, never covenants on\n\
         WHERE its value goes, and no lock can compute parity(a XOR b)."
    );

    Ok(())
}
