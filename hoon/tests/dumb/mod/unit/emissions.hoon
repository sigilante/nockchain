::  tests/dumb/mod/unit/emissions.hoon
::
::    pin tests for the unified Aletheia emissions schedule. Verifies the
::    14-row table at every era boundary, the eon-2 truncation at block
::    65,500, the tail floor of 64 NOCK, and the exact-cap accounting
::    invariant that cumulative supply through block 16,144,876 equals
::    2^32 NOCK.
/=  emission  /common/schedule
/=  *  /common/zeke
/=  *  /common/test
=>
|%
++  ape  atoms-per-nock:emission  :: 2^16
++  reward
  |=  nock-amount=@
  ^-  @
  (mul nock-amount ape)
--
|%
::
::  +test-emissions-genesis: block 0 emits zero atoms.
++  test-emissions-genesis  ^-  tang
  (expect-eq !>(0) !>((schedule:emission 0)))
::
::  +test-emissions-eon-0: blocks 1..=13,150 emit 65,536 NOCK = 2^32 atoms.
++  test-emissions-eon-0  ^-  tang
  =/  expected  ^~((reward (bex 16)))
  ;:  weld
    (expect-eq !>(expected) !>((schedule:emission 1)))
    (expect-eq !>(expected) !>((schedule:emission 13.150)))
  ==
::
::  +test-emissions-eon-1: blocks 13,151..=39,448 emit 32,768 NOCK = 2^31 atoms.
++  test-emissions-eon-1  ^-  tang
  =/  expected  ^~((reward (bex 15)))
  ;:  weld
    (expect-eq !>(expected) !>((schedule:emission 13.151)))
    (expect-eq !>(expected) !>((schedule:emission 39.448)))
  ==
::
::  +test-emissions-eon-2: blocks 39,449..=65,500 emit 16,384 NOCK = 2^30 atoms.
::    eon 2 is truncated from its original end at block 78,895.
++  test-emissions-eon-2  ^-  tang
  =/  expected  ^~((reward (bex 14)))
  ;:  weld
    (expect-eq !>(expected) !>((schedule:emission 39.449)))
    (expect-eq !>(expected) !>((schedule:emission 65.500)))
  ==
::
::  +test-emissions-activation-boundary: block 65,501 (the first post-
::    activation block) emits exactly 2,048 NOCK.
++  test-emissions-activation-boundary  ^-  tang
  =/  expected  (reward 2.048)
  (expect-eq !>(expected) !>((schedule:emission 65.501)))
::
::  +test-emissions-eon-3: blocks 65,501..=170,500 emit 2,048 NOCK each.
++  test-emissions-eon-3  ^-  tang
  =/  expected  (reward 2.048)
  ;:  weld
    (expect-eq !>(expected) !>((schedule:emission 65.501)))
    (expect-eq !>(expected) !>((schedule:emission 170.500)))
  ==
::
::  +test-emissions-decay-table: pin every era boundary in the smooth
::    decay phase.
++  test-emissions-decay-table  ^-  tang
  ;:  weld
    (expect-eq !>((reward 1.536)) !>((schedule:emission 170.501)))
    (expect-eq !>((reward 1.536)) !>((schedule:emission 380.500)))
    (expect-eq !>((reward 1.024)) !>((schedule:emission 380.501)))
    (expect-eq !>((reward 1.024)) !>((schedule:emission 590.500)))
    (expect-eq !>((reward 768)) !>((schedule:emission 590.501)))
    (expect-eq !>((reward 768)) !>((schedule:emission 800.500)))
    (expect-eq !>((reward 512)) !>((schedule:emission 800.501)))
    (expect-eq !>((reward 512)) !>((schedule:emission 1.010.500)))
    (expect-eq !>((reward 384)) !>((schedule:emission 1.010.501)))
    (expect-eq !>((reward 384)) !>((schedule:emission 1.220.500)))
    (expect-eq !>((reward 256)) !>((schedule:emission 1.220.501)))
    (expect-eq !>((reward 256)) !>((schedule:emission 1.430.500)))
    (expect-eq !>((reward 192)) !>((schedule:emission 1.430.501)))
    (expect-eq !>((reward 192)) !>((schedule:emission 1.640.500)))
    (expect-eq !>((reward 128)) !>((schedule:emission 1.640.501)))
    (expect-eq !>((reward 128)) !>((schedule:emission 1.850.500)))
    (expect-eq !>((reward 96)) !>((schedule:emission 1.850.501)))
    (expect-eq !>((reward 96)) !>((schedule:emission 2.060.500)))
  ==
::
::  +test-emissions-tail-floor: blocks 2,060,501..=16,144,876 emit 64 NOCK.
++  test-emissions-tail-floor  ^-  tang
  =/  expected  (reward 64)
  ;:  weld
    (expect-eq !>(expected) !>((schedule:emission 2.060.501)))
    (expect-eq !>(expected) !>((schedule:emission 5.000.000)))
    (expect-eq !>(expected) !>((schedule:emission 10.000.000)))
    (expect-eq !>(expected) !>((schedule:emission 16.144.876)))
  ==
::
::  +test-emissions-post-cap: blocks past tail-end emit zero atoms.
++  test-emissions-post-cap  ^-  tang
  ;:  weld
    (expect-eq !>(0) !>((schedule:emission 16.144.877)))
    (expect-eq !>(0) !>((schedule:emission 20.000.000)))
    (expect-eq !>(0) !>((schedule:emission 100.000.000)))
  ==
::
::  +test-emissions-supply-eon-0: cumulative ++ schedule sums match the
::    expected per-eon emission for the (cheap-to-iterate) eon 0.
::    13,150 blocks * 65,536 NOCK = 861,798,400 NOCK = 861,798,400 * 2^16 atoms.
++  test-emissions-supply-eon-0  ^-  tang
  =/  expected-atoms  (mul 861.798.400 ape)
  (expect-eq !>(expected-atoms) !>((total-supply:emission 13.151)))
::
::  +test-emissions-supply-totals-to-cap: ANALYTIC supply check.
::    Iterating ++ total-supply through the full ~16M-block schedule is
::    impractical, so this test sums the per-eon contributions in closed
::    form and asserts the result equals exactly 2^32 NOCK in atoms.
::    Proves that the tail lands the cap exactly.
++  test-emissions-supply-totals-to-cap  ^-  tang
  =/  eon-0=@  (mul 13.150 (bex 16))                    :: 13,150 * 2^16 NOCK
  =/  eon-1=@  (mul 26.298 (bex 15))                    :: 26,298 * 2^15
  =/  eon-2=@  (mul 26.052 (bex 14))                    :: 26,052 * 2^14
  =/  eon-3=@  (mul 105.000 2.048)
  =/  decay=@
    %+  add  (mul 210.000 1.536)
    %+  add  (mul 210.000 1.024)
    %+  add  (mul 210.000 768)
    %+  add  (mul 210.000 512)
    %+  add  (mul 210.000 384)
    %+  add  (mul 210.000 256)
    %+  add  (mul 210.000 192)
    %+  add  (mul 210.000 128)
    (mul 210.000 96)
  =/  tail=@   (mul 14.084.376 64)
  =/  total-nock=@  :(add eon-0 eon-1 eon-2 eon-3 decay tail)
  (expect-eq !>(`@`(bex 32)) !>(total-nock))
--
