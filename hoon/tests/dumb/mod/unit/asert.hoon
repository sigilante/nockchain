::  tests/dumb/mod/unit/asert.hoon
::
::    unit tests for the aserti3-2d difficulty adjustment library.
/=  asert  /apps/dumbnet/lib/asert
/=  tx-engine  /common/tx-engine
/=  *  /common/zeke
/=  *  /common/test
::
=>
|%
::  fixed test parameters that match post-activation mainnet intent
::  (IDEAL=150, HALF_LIFE=12h=43200). anchor chosen at a small height
::  with a small anchor-target so tests are easy to reason about.
++  ideal  150
++  hl  43.200
++  rb  16
++  rad  ^~((bex 16))
++  anchor-h    1.000
++  anchor-ts   1.000.000
++  anchor-tgt  (bex 200)  :: arbitrary mid-range target atom
++  max-tgt  ^~((dec (bex 256)))
::
::  +on-schedule-call: ASERT with parent on its expected schedule for a
::    child at height (anchor-h + blocks-since). under the anchor-own-ts
::    convention, the parent is (blocks-since - 1) blocks past the anchor,
::    so its on-schedule timestamp is anchor-ts + (blocks-since - 1) * ideal.
::    blocks-since must be >= 1 (the library requires current > anchor).
::    result should be ~= anchor-tgt (within polynomial error at boundaries).
++  on-schedule
  |=  [blocks-since=@ anchor=@]
  ^-  @
  %-  compute-target:asert
  :*  anchor
      anchor-ts
      anchor-h
      (add anchor-ts (mul (dec blocks-since) ideal))
      (add anchor-h blocks-since)
      ideal
      hl
      max-tgt
  ==
::
::  +drift: ASERT where parent's timestamp is off-schedule by +drift-secs
::    relative to its expected on-schedule value (anchor-ts + (blocks-since
::    - 1) * ideal). blocks-since must be >= 1.
++  drift
  |=  [blocks-since=@ drift-secs=@s anchor=@]
  ^-  @
  =/  scheduled  (add anchor-ts (mul (dec blocks-since) ideal))
  =/  current-ts
    ?:  (syn:si drift-secs)
      (add scheduled (abs:si drift-secs))
    (sub scheduled (abs:si drift-secs))
  %-  compute-target:asert
  :*  anchor
      anchor-ts
      anchor-h
      current-ts
      (add anchor-h blocks-since)
      ideal
      hl
      max-tgt
  ==
::
::  +ref-compute-target: independent reference implementation using +si
::    a separate code path that tracks signs via the signed-integer core,
::    used to cross-check +compute-target.
++  ref-compute-target
  |=  $:  anchor-target=@
          anchor-ts=@
          anchor-height=@
          current-ts=@
          current-height=@
          ideal=@
          half-life=@
          max-target=@
      ==
  ^-  @
  ?<  (lte current-height anchor-height)
  =+  si
  =/  td=@s  (dif (sun current-ts) (sun anchor-ts))
  =/  bsa=@  (sub current-height anchor-height)
  =/  id=@s  (sun (mul ideal (dec bsa)))
  =/  exp=@s  (fra (pro (dif td id) (sun (bex 16))) (sun half-life))
  ::  decompose exp into (shifts, frac) matching arithmetic-shift semantics
  =/  exp-pair  (old exp)    :: [sign @u]
  =/  exp-sign  -.exp-pair
  =/  exp-mag   +.exp-pair
  =/  rem-mag  (mod exp-mag (bex 16))
  =/  quo-mag  (rsh [0 16] exp-mag)
  =/  shifts-sign=?
    ?:  exp-sign  %.y
    ?:  =(0 rem-mag)  %.n
    %.n
  =/  shifts-mag=@
    ?:  exp-sign  quo-mag
    ?:  =(0 rem-mag)  quo-mag
    +(quo-mag)
  =/  frac=@
    ?:  exp-sign  rem-mag
    ?:  =(0 rem-mag)  0
    (sub (bex 16) rem-mag)
  ::  same polynomial as the library
  =/  f2  (mul frac frac)
  =/  f3  (mul f2 frac)
  =/  num  :(add (mul 195.766.423.245.049 frac) (mul 971.821.376 f2) (mul 5.127 f3))
  =/  factor  (add (bex 16) (rsh [0 48] (add num (bex 47))))
  =/  unshifted  (mul anchor-target factor)
  =/  max-bits  (met 0 max-target)
  =/  result=@
    ?:  shifts-sign
      =/  cap  (add max-bits 18)
      =/  eff  ?:((gth shifts-mag cap) cap shifts-mag)
      (rsh [0 16] (lsh [0 eff] unshifted))
    =/  ubits  (met 0 unshifted)
    ?:  (gte shifts-mag ubits)  0
    (rsh [0 16] (rsh [0 shifts-mag] unshifted))
  ?:  =(0 result)  1
  ?:  (gth result max-target)  max-target
  result
::
::  BCH aserti3-2d parameters used by published test vectors
++  bch-ideal       600
++  bch-halflife    172.800
::  +bch-max-target: POW limit (expansion of nBits 0x1d00ffff)
++  bch-max-target  (lsh [0 208] 0xffff)
::
::  +bch-nbits-to-target: expand 32-bit compact nBits into target atom.
::
::    top byte is exponent e; low 24 bits are mantissa m.
::    target = m << 8*(e-3) when e >= 3, else m >> 8*(3-e).
::    matches bitcoin's CompactToUint256 for the values that appear in
::    the aserti3-2d qa vectors (no sign bit cases).
++  bch-nbits-to-target
  |=  nbits=@
  ^-  @
  =/  exp       (rsh [0 24] nbits)
  =/  mantissa  (dis nbits 0xff.ffff)
  ?:  (gte exp 3)
    (lsh [0 (mul 8 (sub exp 3))] mantissa)
  (rsh [0 (mul 8 (sub 3 exp))] mantissa)
::
::  +target-to-nbits: compact a target atom back into 32-bit nBits form.
::
::    mirrors bitcoin's arith_uint256::GetCompact for non-negative values.
::    if the top bit of the 24-bit mantissa would be set, shift right one
::    byte and increment the exponent (avoiding the sign-bit collision).
++  target-to-nbits
  |=  target=@
  ^-  @
  ?:  =(0 target)  0
  =/  size  (div (add (met 0 target) 7) 8)
  =/  compact=@
    ?:  (lte size 3)
      (lsh [0 (mul 8 (sub 3 size))] target)
    (rsh [0 (mul 8 (sub size 3))] target)
  ?:  =(0 (dis compact 0x80.0000))
    (con (lsh [0 24] size) compact)
  (con (lsh [0 24] +(size)) (rsh [0 8] compact))
::
::  +bch-vector-check: cross-check one BCH aserti3-2d qa vector.
::
::    anchor-min-ts as published in the BCH vectors is the anchor's PARENT
::    time (BCH convention, PDF §1.3 Option 1). our library uses the
::    anchor-own-ts convention (Option 2), so we shift by +bch-ideal on
::    entry to convert t_{M-1} → t_M. this is an algebraic identity: the
::    delta that drives the exponent is unchanged, because our code also
::    uses blocks-since-anchor = child.height - anchor.height (which is
::    BCH's height_diff + 1), and (td_bch - ideal) - ideal*(bsa - 1)
::    = td_bch - ideal*bsa = td_bch - ideal*(height_diff_bch + 1).
::    each iter row gives (parent-height, parent-time, expected child-nbits);
::    we compute the target for the child at parent-height+1 and require it
::    to compact exactly back to the expected nbits.
++  bch-vector-check
  |=  $:  anchor-height=@
          anchor-min-ts=@
          anchor-nbits=@
          iters=(list [pheight=@ ptime=@ expected-nbits=@])
      ==
  ^-  ?
  =/  anchor-target  (bch-nbits-to-target anchor-nbits)
  ::  shift BCH's anchor_parent-time into our anchor-own-time convention.
  =/  nc-anchor-min-ts  (add anchor-min-ts bch-ideal)
  |-
  ?~  iters  %.y
  =/  got
    %-  compute-target:asert
    :*  anchor-target
        nc-anchor-min-ts
        anchor-height
        ptime.i.iters
        +(pheight.i.iters)
        bch-ideal
        bch-halflife
        bch-max-target
    ==
  ?.  =((target-to-nbits got) expected-nbits.i.iters)
    %.n
  $(iters t.iters)
--
::
|%
::
::  +test-asert-bch-nbits-expansion: compact nBits → full target atom
::    pins three values taken from the BCH aserti3-2d QA vectors:
::      0x1d00ffff → 0xffff << 208   (POW limit, anchor of runs 01/05)
::      0x01010000 → 1               (minimum target, anchor of run 03)
::      0x1802aee8 → 0x2aee8 << 168  (mid target, anchor of runs 06-12)
++  test-asert-bch-nbits-expansion
  =/  got
    :+  (bch-nbits-to-target 0x1d00.ffff)
        (bch-nbits-to-target 0x101.0000)
    (bch-nbits-to-target 0x1802.aee8)
  =/  expected  [(lsh [0 208] 0xffff) 1 (lsh [0 168] 0x2.aee8)]
  (expect-eq !>(expected) !>(got))
::
::  +test-asert-bch-nbits-roundtrip: expanding and re-compacting canonical
::    nBits values must round-trip exactly. pins the values that appear as
::    anchor targets and as results across the BCH qa vector suite.
++  test-asert-bch-nbits-roundtrip
  =/  samples=(list @)
    :~  0x1d00.ffff
        0x1c7f.62c0
        0x1a2b.3c4d
        0x101.0000
        0x102.0000
        0x200.8000
        0x1802.aee8
        0x1802.ad91
        0x1802.abf8
        0x1802.a6b7
        0x1726.9f86
    ==
  =/  roundtripped  (turn samples |=(n=@ (target-to-nbits (bch-nbits-to-target n))))
  (expect-eq !>(samples) !>(roundtripped))
::
::  +test-asert-bch-run01: steady 600s blocks at POW limit (BCH qa run01).
++  test-asert-bch-run01
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1d00.ffff
    :~  [2 1.200 0x1d00.ffff]
        [3 1.800 0x1d00.ffff]
        [4 2.400 0x1d00.ffff]
        [5 3.000 0x1d00.ffff]
        [6 3.600 0x1d00.ffff]
        [7 4.200 0x1d00.ffff]
        [8 4.800 0x1d00.ffff]
        [9 5.400 0x1d00.ffff]
        [10 6.000 0x1d00.ffff]
        [11 6.600 0x1d00.ffff]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run02: steady 600s blocks at arbitrary mid target.
++  test-asert-bch-run02
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1a2b.3c4d
    :~  [2 1.200 0x1a2b.3c4d]
        [3 1.800 0x1a2b.3c4d]
        [4 2.400 0x1a2b.3c4d]
        [5 3.000 0x1a2b.3c4d]
        [6 3.600 0x1a2b.3c4d]
        [7 4.200 0x1a2b.3c4d]
        [8 4.800 0x1a2b.3c4d]
        [9 5.400 0x1a2b.3c4d]
        [10 6.000 0x1a2b.3c4d]
        [11 6.600 0x1a2b.3c4d]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run03: steady 600s blocks at minimum target.
++  test-asert-bch-run03
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x101.0000
    :~  [2 1.200 0x101.0000]
        [3 1.800 0x101.0000]
        [4 2.400 0x101.0000]
        [5 3.000 0x101.0000]
        [6 3.600 0x101.0000]
        [7 4.200 0x101.0000]
        [8 4.800 0x101.0000]
        [9 5.400 0x101.0000]
        [10 6.000 0x101.0000]
        [11 6.600 0x101.0000]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run04: halflife schedule jumps, target doubling.
::    each iter adds 173.400s between blocks (= 1 halflife above schedule
::    per block), so target doubles every block. exercises positive-shift
::    path at whole-exponent steps.
++  test-asert-bch-run04
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x101.0000
    :~  [2 174.000 0x102.0000]
        [3 347.400 0x104.0000]
        [4 520.800 0x108.0000]
        [5 694.200 0x110.0000]
        [6 867.600 0x120.0000]
        [7 1.041.000 0x140.0000]
        [8 1.214.400 0x200.8000]
        [9 1.387.800 0x201.0000]
        [10 1.561.200 0x202.0000]
        [11 1.734.600 0x204.0000]
        [12 1.908.000 0x208.0000]
        [13 2.081.400 0x210.0000]
        [14 2.254.800 0x220.0000]
        [15 2.428.200 0x240.0000]
        [16 2.601.600 0x300.8000]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run05: halflife block-height jumps, target halving.
::    each iter advances 288 heights with zero elapsed time (= ~1 halflife
::    below schedule per 288 blocks), so target halves. exercises negative
::    -shift path including iters that straddle integer exponents.
++  test-asert-bch-run05
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1d00.ffff
    :~  [2 0 0x1d00.fec5]
        [290 0 0x1c7f.62c0]
        [578 0 0x1c3f.b160]
        [866 0 0x1c1f.d8b0]
        [1.154 0 0x1c0f.ec58]
        [1.442 0 0x1c07.f62c]
        [1.730 0 0x1c03.fb16]
        [2.018 0 0x1c01.fd8b]
        [2.306 0 0x1c00.fec5]
        [2.594 0 0x1b7f.62c0]
        [2.882 0 0x1b3f.b160]
        [3.170 0 0x1b1f.d8b0]
        [3.458 0 0x1b0f.ec58]
        [3.746 0 0x1b07.f62c]
        [4.034 0 0x1b03.fb16]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run06: deterministically random solvetimes, stable
::    hashrate around a recent real-life nBits. 1000-iter BCH run; we
::    sample the prefix plus a decile of checkpoints across the trajectory.
++  test-asert-bch-run06
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1802.aee8
    :~  [2 1.200 0x1802.aee8]
        [3 1.310 0x1802.ad91]
        [10 7.099 0x1802.b1f2]
        [12 8.626 0x1802.b2db]
        [21 15.443 0x1802.b6cf]
        [51 34.841 0x1802.bab7]
        [101 63.201 0x1802.b620]
        [201 125.604 0x1802.bcde]
        [501 300.620 0x1802.aef5]
        [801 482.486 0x1802.b422]
        [1.001 589.738 0x1802.91ad]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run07: same random solvetimes but hashrate is
::    up-ramping — targets fall, exercising more iterations of the
::    negative-shift arm as the network gets harder.
++  test-asert-bch-run07
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1802.aee8
    :~  [2 1.200 0x1802.aee8]
        [3 1.310 0x1802.ad91]
        [10 7.099 0x1802.b1f2]
        [12 8.141 0x1802.b181]
        [21 11.548 0x1802.ac07]
        [51 16.876 0x1802.8a2d]
        [101 20.372 0x1802.4899]
        [201 24.359 0x1801.d2e0]
        [501 29.563 0x1800.e793]
        [801 32.280 0x1771.ba06]
        [1.001 33.365 0x1746.9789]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run08: same random solvetimes, down-ramping hashrate.
::    targets rise and saturate at POW limit by iter 493 — validates the
::    positive-shift clamp path.
++  test-asert-bch-run08
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1802.aee8
    :~  [2 1.200 0x1802.aee8]
        [3 1.310 0x1802.ad91]
        [10 7.099 0x1802.b1f2]
        [12 9.595 0x1802.b58d]
        [21 23.229 0x1802.cce4]
        [51 96.281 0x1803.7de7]
        [101 333.916 0x1808.07f0]
        [201 1.336.050 0x1901.5fa0]
        [301 3.021.970 0x1a03.a5c8]
        [401 4.883.769 0x1b13.9eeb]
        [501 7.462.933 0x1d00.ffff]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run09: 300s blocks straddling the signed-32-bit
::    height boundary. verifies asert makes no use of signed int types
::    for heights or timestamps.
++  test-asert-bch-run09
  =/  ok
    %-  bch-vector-check
    :^    2.147.483.642
        1.234.567.290
      0x1802.aee8
    :~  [2.147.483.643 1.234.568.190 0x1802.ae16]
        [2.147.483.644 1.234.568.490 0x1802.ad44]
        [2.147.483.645 1.234.568.790 0x1802.ac71]
        [2.147.483.646 1.234.569.090 0x1802.ab9e]
        [2.147.483.647 1.234.569.390 0x1802.aacd]
        [2.147.483.648 1.234.569.690 0x1802.a9fa]
        [2.147.483.649 1.234.569.990 0x1802.a929]
        [2.147.483.650 1.234.570.290 0x1802.a858]
        [2.147.483.651 1.234.570.590 0x1802.a787]
        [2.147.483.652 1.234.570.890 0x1802.a6b7]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run10: 900s blocks straddling the signed-64-bit
::    height boundary. hoon atoms are unbounded so this only exercises
::    that our arithmetic still works past 2^63, but serves as a parity
::    check against BCH's published reference vectors.
++  test-asert-bch-run10
  =/  ok
    %-  bch-vector-check
    :^    9.223.372.036.854.775.802
        2.147.483.047
      0x1802.aee8
    :~  [9.223.372.036.854.775.803 2.147.484.547 0x1802.afbb]
        [9.223.372.036.854.775.804 2.147.485.447 0x1802.b08f]
        [9.223.372.036.854.775.805 2.147.486.347 0x1802.b166]
        [9.223.372.036.854.775.806 2.147.487.247 0x1802.b23a]
        [9.223.372.036.854.775.807 2.147.488.147 0x1802.b30e]
        [9.223.372.036.854.775.808 2.147.489.047 0x1802.b3e5]
        [9.223.372.036.854.775.809 2.147.489.947 0x1802.b4bb]
        [9.223.372.036.854.775.810 2.147.490.847 0x1802.b592]
        [9.223.372.036.854.775.811 2.147.491.747 0x1802.b669]
        [9.223.372.036.854.775.812 2.147.492.647 0x1802.b73d]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run11: deterministically random uniform solvetimes
::    with negative-time iterations mixed in. targets drift down over the
::    1000-iter run as the simulated hashrate shifts.
++  test-asert-bch-run11
  =/  ok
    %-  bch-vector-check
    :^    1
        0
      0x1802.aee8
    :~  [2 1.200 0x1802.aee8]
        [3 1.496 0x1802.ae12]
        [4 1.398 0x1802.ac28]
        [5 1.996 0x1802.ac28]
        [11 3.289 0x1802.a5df]
        [21 4.571 0x1802.992f]
        [51 14.779 0x1802.84bc]
        [101 29.800 0x1802.5f23]
        [501 151.798 0x1801.7a32]
        [1.000 293.956 0x1800.c943]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-bch-run12: each block arrives 1s before the previous.
::    around iter 1200 the parent-time crosses below the anchor's own
::    parent-time (10.000s), which flips the sign of (current-min-ts -
::    anchor-min-ts) and drives +compute-exponent through its negative
::    time-diff branch. the 10.000-iter run finishes with parent-time
::    far below anchor, forcing the exponent's sign-magnitude arithmetic
::    to route large magnitudes through shifts.
++  test-asert-bch-run12
  =/  ok
    %-  bch-vector-check
    :^    1
        10.000
      0x1802.aee8
    :~  [2 11.200 0x1802.aee8]
        [3 11.199 0x1802.ad44]
        [11 11.191 0x1802.a033]
        [101 11.101 0x1802.1d10]
        [1.001 10.201 0x173d.caa1]
      ::  boundary slice: parent-time approaches 10.000 then drops below
        [1.196 10.006 0x1726.9f86]
        [1.197 10.005 0x1726.87a0]
        [1.198 10.004 0x1726.6fe6]
        [1.199 10.003 0x1726.5856]
        [1.200 10.002 0x1726.40b0]
        [1.201 10.001 0x1726.290b]
        [1.202 10.000 0x1726.117b]
        [1.203 9.999 0x1725.fa01]
        [1.204 9.998 0x1725.e29c]
        [1.205 9.997 0x1725.cb37]
        [1.206 9.996 0x1725.b3e7]
        [1.207 9.995 0x1725.9cad]
      ::  past the boundary: parent-time < anchor-parent-time throughout
        [1.211 9.991 0x1725.4030]
        [5.001 6.201 0x1601.06b7]
        [10.000 1.202 0x1364.7d71]
    ==
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-poly-factor-zero: polynomial is exactly RADIX at frac=0
++  test-asert-poly-factor-zero
  %+  expect-eq  !>(rad)
  !>((poly-factor:asert 0))
::
::  +test-asert-poly-factor-monotonic: polynomial is non-decreasing in frac.
::    the integer approximation is strictly monotonic in the reals but loses
::    precision near frac=0 (the linear term dominated by >>48 rounds to zero
::    until frac crosses the truncation threshold). gte, not gth.
++  test-asert-poly-factor-monotonic
  =/  samples=(list @)
    ~[0 1 100 1.000 10.000 20.000 30.000 40.000 50.000 60.000 65.535]
  =/  vals  (turn samples poly-factor:asert)
  =|  ok=?
  =.  ok  %.y
  =/  prev  0
  |-
  ?~  vals  (expect-eq !>(%.y) !>(ok))
  =.  ok  &(ok (gte i.vals prev))
  $(vals t.vals, prev i.vals)
::
::  +test-asert-poly-factor-rejects-oversized-frac: +poly-factor enforces
::    its documented precondition (frac < radix). calling at frac = radix
::    and frac = radix + 1 must crash on the `?>` guard.
++  test-asert-poly-factor-rejects-oversized-frac
  ;:  weld
    %+  expect-fail  |.((poly-factor:asert rad))  ~
    %+  expect-fail  |.((poly-factor:asert +(rad)))  ~
  ==
::
::  +test-asert-poly-factor-near-one: at y=1 the polynomial is close to 2*RADIX
++  test-asert-poly-factor-near-one
  =/  v  (poly-factor:asert 65.535)
  ::  2^(65535/65536) * 65536 is in [131,064, 131,072].
  ::  we assert v is within 200 of the ideal — well within the 0.13% bound.
  =/  ideal-v  131.070
  =/  diff  ?:((gte v ideal-v) (sub v ideal-v) (sub ideal-v v))
  (expect-eq !>(%.y) !>((lth diff 200)))
::
::  +test-asert-poly-factor-reversible: PDF §1.2 reversibility under the
::    polynomial approximation. since 2^y * 2^(1-y) = 2 exactly, we require
::    poly-factor(f) * poly-factor(radix - f) to approximate 2 * radix^2
::    for any f in (0, radix). the polynomial has max error 0.13% per
::    evaluation, so the product error is bounded by ~0.26%; we allow
::    0.33% of expected to cover rounding corners.
++  test-asert-poly-factor-reversible
  =/  fracs=(list @)  ~[1 16.384 32.768 49.152 65.535]
  =/  expected  (mul 2 (mul rad rad))
  =/  tol  (div expected 300)
  =|  ok=?
  =.  ok  %.y
  =.  ok
    %+  roll  fracs
    |=  [f=@ acc=_ok]
    =/  lhs  (mul (poly-factor:asert f) (poly-factor:asert (sub rad f)))
    =/  diff  ?:((gte lhs expected) (sub lhs expected) (sub expected lhs))
    &(acc (lth diff tol))
  (expect-eq !>(%.y) !>(ok))
::
::  +test-asert-decompose-exponent-corners: isolation-level pins for the
::    five documented corner inputs of +decompose-exponent. exp=0, largest
::    positive fractional (radix-1), smallest negative (-1) which rounds
::    up to shifts=1 with frac=radix-1, exact negative radix (-radix)
::    which stays at shifts=1 with frac=0, and one past (-radix-1) which
::    rolls to shifts=2. shortens the debugging chain if a future refactor
::    perturbs the rounding direction.
++  test-asert-decompose-exponent-corners
  =/  got
    :~  (decompose-exponent:asert %.y 0)
        (decompose-exponent:asert %.y 65.535)
        (decompose-exponent:asert %.n 1)
        (decompose-exponent:asert %.n 65.536)
        (decompose-exponent:asert %.n 65.537)
    ==
  =/  expected
    :~  [%.y 0 0]
        [%.y 0 65.535]
        [%.n 1 65.535]
        [%.n 1 0]
        [%.n 2 65.535]
    ==
  (expect-eq !>(expected) !>(got))
::
::  +test-asert-anchor-identity: first post-anchor block with parent-time
::    at the anchor's own timestamp returns anchor-target exactly. this is
::    the activation boundary: child = anchor + 1, parent IS the anchor, so
::    current-min-timestamp = anchor-min-timestamp, blocks-since-anchor = 1,
::    ideal-total = ideal * 0 = 0, exponent = 0, factor = radix.
++  test-asert-anchor-identity
  =/  got
    %-  compute-target:asert
    :*  anchor-tgt  anchor-ts  anchor-h
        anchor-ts   +(anchor-h)
        ideal  hl  max-tgt
    ==
  (expect-eq !>(anchor-tgt) !>(got))
::
::  +test-asert-on-schedule-approx-identity: N blocks on schedule keeps
::    target near anchor-target (within polynomial approximation error).
::    exponent should be zero, so factor should be exactly RADIX.
++  test-asert-on-schedule-approx-identity
  =/  got-1    (on-schedule 1 anchor-tgt)
  =/  got-10   (on-schedule 10 anchor-tgt)
  =/  got-100  (on-schedule 100 anchor-tgt)
  ::  with exactly zero exponent, factor = RADIX, unshifted = anchor*RADIX,
  ::  result = unshifted >> 16 = anchor exactly.
  %+  expect-eq  !>([anchor-tgt anchor-tgt anchor-tgt])
  !>([got-1 got-10 got-100])
::
::  +test-asert-halflife-doubles: block arrives exactly HALF_LIFE late ⇒
::    target doubles (approximately; polynomial boundary).
::    time_diff - ideal*blocks = HALF_LIFE ⇒ exponent = RADIX ⇒ 2^1 factor.
++  test-asert-halflife-doubles
  =/  got  (drift 1 (sun:si hl) anchor-tgt)
  ::  factor at exponent = 1 is ~131_068 / 65_536 ≈ 1.99994.
  ::  so got ≈ 2 * anchor-tgt (within 0.01%).
  =/  expected  (mul 2 anchor-tgt)
  =/  diff  ?:((gte got expected) (sub got expected) (sub expected got))
  ::  tolerance: 0.01% of expected = expected / 10000
  =/  tol  (div expected 10.000)
  (expect-eq !>(%.y) !>((lth diff tol)))
::
::  +test-asert-halflife-halves: block arrives exactly HALF_LIFE early ⇒
::    target halves.
++  test-asert-halflife-halves
  =/  got  (drift 1 (new:si %.n hl) anchor-tgt)
  =/  expected  (div anchor-tgt 2)
  =/  diff  ?:((gte got expected) (sub got expected) (sub expected got))
  =/  tol  (div expected 10.000)
  (expect-eq !>(%.y) !>((lth diff tol)))
::
::  +test-asert-compute-exponent-negative-time: canary for the third
::    branch of +compute-exponent (time-diff-sign = %.n). reachable in
::    production when a fork produces a parent median-of-11 below the
::    anchor's. covered indirectly via +test-asert-ref-cross-check and
::    +test-asert-halflife-halves; this is a direct isolation pin so any
::    refactor that collapsed the branches would surface here first.
++  test-asert-compute-exponent-negative-time
  =/  a  (compute-exponent:asert %.n 5.000 2 150 43.200)
  =/  b  (compute-exponent:asert %.n 100 10 150 43.200)
  ::  negative time-diff always routes to the third branch, which emits
  ::  sign=%.n regardless of magnitude of ideal-total.
  (expect-eq !>([%.n %.n]) !>([sign.a sign.b]))
::
::  +test-asert-monotonic-timestamp: later timestamp → larger target (easier)
++  test-asert-monotonic-timestamp
  =/  lo  (drift 5 (new:si %.n 5.000) anchor-tgt)
  =/  on  (drift 5 --0 anchor-tgt)
  =/  hi  (drift 5 (sun:si 5.000) anchor-tgt)
  %+  expect-eq  !>(%.y)
  !>  &((lth lo on) (lth on hi))
::
::  +test-asert-monotonic-height: more blocks since anchor at same clock time
::    means blocks are arriving faster than schedule → smaller target (harder).
::    fix current-ts at anchor-ts + 100*ideal, vary blocks-since from 100→110.
++  test-asert-monotonic-height
  =/  fixed-ts  (add anchor-ts (mul 100 ideal))
  =/  mk
    |=  blocks=@
    %-  compute-target:asert
    :*  anchor-tgt  anchor-ts  anchor-h
        fixed-ts  (add anchor-h blocks)
        ideal  hl  max-tgt
    ==
  =/  t100  (mk 100)
  =/  t105  (mk 105)
  =/  t110  (mk 110)
  %+  expect-eq  !>(%.y)
  !>  &((gth t100 t105) (gth t105 t110))
::
::  +test-asert-clamps-max-target: huge positive drift saturates at max-target
++  test-asert-clamps-max-target
  =/  got
    %-  compute-target:asert
    :*  anchor-tgt  anchor-ts  anchor-h
        (add anchor-ts (mul 100 hl))   ::  100 half-lives of drift
        +(anchor-h)
        ideal  hl  max-tgt
    ==
  (expect-eq !>(max-tgt) !>(got))
::
::  +test-asert-clamps-min: huge negative drift saturates at 1
++  test-asert-clamps-min
  =/  got
    %-  compute-target:asert
    :*  anchor-tgt  anchor-ts  anchor-h
        anchor-ts                   ::  zero time passed
        (add anchor-h 1.000.000)    ::  but a million blocks elapsed
        ideal  hl  max-tgt
    ==
  (expect-eq !>(1) !>(got))
::
::  +test-asert-rejects-zero-anchor-target: a misconfigured
::    asert-anchor-target-atom = 0 would multiply through to 0 at
::    every post-activation block and silently clamp to 1 (chain
::    frozen). +compute-target guards the boundary; invoking it with
::    anchor-target = 0 must crash rather than return 1.
++  test-asert-rejects-zero-anchor-target
  %+  expect-fail
    |.
    %-  compute-target:asert
    :*  0  anchor-ts  anchor-h
        anchor-ts  +(anchor-h)
        ideal  hl  max-tgt
    ==
  ~
::
::  +test-asert-ref-cross-check: library and reference impl agree across
::    a grid of (blocks-since, drift, anchor-target) inputs.
++  test-asert-ref-cross-check
  =/  block-samples=(list @)  ~[1 2 10 100 288 576 2.016 10.000]
  =/  drift-samples=(list @s)
    ~[--0 (sun:si 1) (new:si %.n 1) (sun:si 150) (new:si %.n 150) (sun:si 43.200) (new:si %.n 43.200) (sun:si 100.000)]
  =/  target-samples=(list @)
    ~[(bex 128) (bex 200) (bex 240) (div max-tgt 2) max-tgt 1 1.000]
  =|  agree=?
  =.  agree  %.y
  =.  agree
    %+  roll  block-samples
    |=  [blocks=@ a=_agree]
    %+  roll  drift-samples
    |=  [dr=@s b=_a]
    %+  roll  target-samples
    |=  [tgt=@ c=_b]
    =/  scheduled  (add anchor-ts (mul blocks ideal))
    =/  cur-ts
      ?:  (syn:si dr)
        (add scheduled (abs:si dr))
      =/  drift-mag  (abs:si dr)
      ?:  (gth drift-mag scheduled)  0
      (sub scheduled drift-mag)
    =/  lib
      %-  compute-target:asert
      :*  tgt  anchor-ts  anchor-h
          cur-ts  (add anchor-h blocks)
          ideal  hl  max-tgt
      ==
    =/  ref
      %-  ref-compute-target
      :*  tgt  anchor-ts  anchor-h
          cur-ts  (add anchor-h blocks)
          ideal  hl  max-tgt
      ==
    &(c =(lib ref))
  (expect-eq !>(%.y) !>(agree))
::
::  +test-asert-bn-wrapper: +compute-target-bn matches +compute-target
::    after bignum→atom conversion.
++  test-asert-bn-wrapper
  =/  tgt-atom  (bex 180)
  =/  tgt-bn  (chunk:bignum tgt-atom)
  =/  cur-ts  (add anchor-ts (mul 50 ideal))
  =/  cur-h  (add anchor-h 50)
  =/  bn-result
    %-  compute-target-bn:asert
    :*  tgt-bn  anchor-ts  anchor-h
        cur-ts  cur-h
        ideal  hl  max-tgt
    ==
  =/  atom-result
    %-  compute-target:asert
    :*  tgt-atom  anchor-ts  anchor-h
        cur-ts  cur-h
        ideal  hl  max-tgt
    ==
  (expect-eq !>(atom-result) !>((merge:bignum bn-result)))
--
