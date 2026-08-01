//! kick: evaluate a honk/hoonc build trap and jam the result.
//!
//! `kick <trap.jam> <out.jam> [axis]`
//!
//! Cues the input jam, fires the trap ([9 2 0 1]) under the native
//! hot state with formula-keyed jet dispatch (HintBlind) — the same
//! evaluation environment honk itself uses — then jams the noun at
//! `axis` of the result (default 1, the whole value) to the output.
//!
//! Built for the Jock corpus harness (jock tools/vex.sh): honk
//! `--arbitrary` output is a deferred vase trap; this is the missing
//! "run it" step for any downstream consumer of build artifacts.
//!
//! Build & install:
//!
//!     cargo build --release -p honk --bin kick
//!     cp target/release/kick ~/.cargo/bin/honk-kick
//!
//! Example (value of an --arbitrary build; axis 3 for the vase tail):
//!
//!     honk --new --arbitrary --output out.jam --prelude hoon-138.hoon entry.hoon deps/
//!     honk-kick out.jam value.jam

use std::{env, fs, process};

use honk::native::hot::native_hot_state;
use nockapp::noun::slab::{NockJammer, NounSlab};
use nockapp::utils::{create_context, NOCK_STACK_SIZE_MEDIUM};
use nockvm::ext::NounExt;
use nockvm::interpreter::{interpret, Context, Error as NockError};
use nockvm::jets::cold::Cold;
use nockvm::jets::JetDispatchMode;
use nockvm::mem::NockStack;
use nockvm::noun::{Noun, D, T};

fn create_eval_context() -> Context {
    let mut stack = NockStack::new(NOCK_STACK_SIZE_MEDIUM, 0);
    let cold = Cold::new(&mut stack);
    create_context(
        stack,
        native_hot_state(),
        cold,
        None,
        vec![],
        JetDispatchMode::HintBlind,
    )
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: kick <trap.jam> <out.jam> [axis]");
        process::exit(64);
    }
    let axis: u64 = if args.len() > 3 {
        args[3].parse().expect("axis must be a u64")
    } else {
        1
    };
    let jam = fs::read(&args[1]).expect("read input jam");
    let mut ctx = create_eval_context();
    let result: Result<Noun, NockError> = unsafe {
        ctx.with_stack_frame(0, |context: &mut Context| {
            let trap = <Noun as NounExt>::cue_bytes_slice(&mut context.stack, &jam)
                .expect("cue input jam");
            let kick = T(&mut context.stack, &[D(9), D(2), D(0), D(1)]);
            interpret(context, trap, kick)
        })
    };
    match result {
        Ok(val) => {
            let space = ctx.stack.noun_space();
            let mut cur = val;
            let mut path = Vec::new();
            let mut ax = axis;
            while ax > 1 {
                path.push(ax & 1);
                ax >>= 1;
            }
            for bit in path.iter().rev() {
                let cell = cur
                    .in_space(&space)
                    .as_cell()
                    .expect("axis descends into atom");
                cur = if *bit == 0 {
                    cell.head().noun()
                } else {
                    cell.tail().noun()
                };
            }
            let mut slab: NounSlab<NockJammer> = NounSlab::new();
            let root = slab.copy_into(cur, &space);
            slab.set_root(root);
            fs::write(&args[2], slab.jam().to_vec()).expect("write output jam");
        }
        Err(err) => {
            eprintln!("kick: crashed: {err:?}");
            process::exit(1);
        }
    }
}
