::  Scale benchmark for the 2026-04-18 LAX1 kernel-livelock hypothesis.
::
::  Context (docs/incidents/lax1-stall-20260420/README.md): the serf
::  thread entered a CPU-bound loop shortly after an accept-block event.
::  The nous-era +block-request-effects-from in inner.hoon rebuilds
::  +pending-block-heights (a full z-by fold over pending-blocks) on
::  every new-heaviest accept-block, turning per-accept cost into
::  O(|pending-blocks|). If pending-blocks accumulates under real peer
::  load faster than +garbage-collect (which runs only on new-heaviest
::  with a 20-height retention window) can drain it, accept-block cost
::  grows linearly in pending size.
::
::  These benchmarks do NOT assert a timing bound — Hoon test-runner
::  granularity is second-level, which is too coarse for microbench
::  assertions. They exist so operators running `roswell --new bench-dumb`
::  see wall-clock deltas between the empty-pending baseline and the
::  seeded-pending variants. Pair with external profiling (RUST_LOG
::  trace for %slog.[0 %accept-block ...] timestamps) to see per-arm
::  cost.
::
::  Concrete call sites touched (inner.hoon):
::  - ++block-request-effects-from      line ~1061
::  - ++pending-block-heights           line ~1052
::  - ++garbage-collect  (consensus)    line ~779
::
/=  helpers  /tests/dumb/helpers
/=  txe  /common/tx-engine
/=  *  /common/test
|%
++  h  ~(. helpers bc-pending-integration-tests:helpers)
++  t  ~(. txe bc-pending-integration-tests:helpers)
::
::  Shared helper: build a chain of depth `n` above genesis, then for
::  each height in [2..n] construct a competing block that references
::  a raw-tx the node has never heard. Each such block is a valid
::  sibling of the canonical chain block at that height but with a
::  distinct block-id, so it lands in pending-blocks with no risk of
::  being accepted. Returns (a) the populated nockchain, (b) the
::  canonical-chain page at height n for subsequent accept-block work.
::
::  Pending-blocks grows by (n - 1) entries. Garbage collection has
::  not yet run for the seeded entries because their heard-at is the
::  current heaviest height — retention keeps them alive until the
::  tip advances another 20 past the seed time.
++  seed-pending-at-heights
  |=  n=@
  ^-  [tip=page:t nockchain=_nockchain:h]
  ::  build the canonical chain to height n
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages=(list page:t)  nockchain
    (add-n-pages-integration:h genesis n nockchain)
  ::  for each height >= 2, seed a competing pending block. snag is
  ::  zero-indexed so (snag 0 pages) is height 1. We iterate indices
  ::  1..(n-1) which correspond to heights 2..n.
  =/  tip=page:t  (snag (dec n) pages)
  =|  i=@
  |-
  ?:  (gte i (dec n))
    [tip nockchain]
  =/  parent=page:t  (snag i pages)
  ::  competing raw-tx referencing the coinbase of `parent`. Each
  ::  iteration uses a different recipient key so the tx-id differs
  ::  across heights; the tx itself is never heard by the node, so
  ::  the crafted block at height (i+2) enters pending-blocks.
  =/  recipient=sig:t
    ?:  =((mod i 3) 0)
      p:default-keys-1:h
    ?:  =((mod i 3) 1)
      p:default-keys-2:h
    p:default-keys-3:h
  =/  raw=raw-tx:v0:t
    (make-raw-tx-from-coinbase:v0:h recipient parent)
  =/  pending=page:t  (make-page-with-txs:v0:h parent ~[id.raw])
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) pending)
  $(i +(i))
::
::  Baseline: accept one new-heaviest block with no pending-blocks
::  backlog. Establishes the "empty pending-blocks" per-accept cost
::  so operators can compare against the seeded variants below.
++  bench-accept-block-empty-pending
  =+  [nockchain genesis]=init-nockchain:h
  ::  build up to height 50 without any pending-blocks accumulation.
  =^  pages=(list page:t)  nockchain
    (add-n-pages-integration:h genesis 50 nockchain)
  ::  now accept one more block — this is the timed operation.
  =/  tip=page:t  (snag 49 pages)
  =/  new-block  (make-empty-page:h tip)
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) new-block)
  ~
::
::  With 100 pending-blocks seeded, how long does the next accept-block
::  take? Seeding walks +heard-block 99 times, then we trigger one
::  accept-block above the seeded tip; the +block-request-effects-from
::  call on that accept-block is the O(|pending|) work under test.
++  bench-accept-block-100-pending
  =/  [tip=page:t nockchain=_nockchain:h]
    (seed-pending-at-heights 100)
  =/  new-block  (make-empty-page:h tip)
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) new-block)
  ~
::
::  500 pending-blocks. If accept-block latency is linear in
::  |pending-blocks|, this should run roughly 5x slower than the
::  baseline. A test that takes dramatically longer than 5x the
::  baseline suggests super-linear behaviour (e.g. nested z-by folds
::  in code paths we haven't yet audited).
++  bench-accept-block-500-pending
  =/  [tip=page:t nockchain=_nockchain:h]
    (seed-pending-at-heights 500)
  =/  new-block  (make-empty-page:h tip)
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) new-block)
  ~
::
::  1000 pending-blocks. Stresses the upper bound of what LAX1 might
::  realistically accumulate over the ~12h window preceding the stall.
++  bench-accept-block-1000-pending
  =/  [tip=page:t nockchain=_nockchain:h]
    (seed-pending-at-heights 1.000)
  =/  new-block  (make-empty-page:h tip)
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) new-block)
  ~
::
::  5000 pending-blocks. If the terminal accept-block's
::  +block-request-effects-from walk is the livelock source on LAX1
::  (which had poke_timeout_secs = 180 in production), this bench
::  should approach or exceed that ceiling. Running within the
::  timeout weakens the hypothesis; running over it strengthens it.
::  Setup alone is ~5000 heard-block invocations; on dev hardware
::  expect several minutes for the arm as a whole.
++  bench-accept-block-5000-pending
  =/  [tip=page:t nockchain=_nockchain:h]
    (seed-pending-at-heights 5.000)
  =/  new-block  (make-empty-page:h tip)
  =^  *  nockchain
    (~(heard-block k-by:h nockchain) new-block)
  ~
--
