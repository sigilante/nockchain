::  tests/wallet/mod/state-upgrade.hoon
::
::    unit tests for the wallet's two cascading blockchain-constants
::    schema bumps:
::      - state-6 freezes the pre-ASERT shape (no asert-* fields),
::      - state-7 freezes the phase-1 shape (five asert-* fields, no
::        asert-anchor-min-timestamp),
::      - state-8 carries the full post-phase-2 blockchain-constants.
::    Each step must preserve old persisted states' ability to decode.
/=  *    /common/test
/=  *    /common/zeke
/=  wt   /apps/wallet/lib/types
/=  txe  /common/tx-engine
|%
::
::  fix-3b (a): state-6's bc field uses blockchain-constants-v1-pre-asert
::  (no asert-* trailing fields). state-7's bc uses
::  blockchain-constants-v1-phase-1 (five asert-* fields, no
::  asert-anchor-min-timestamp). their default nouns must differ.
++  test-fix3b-state-6-bc-shape-differs-from-state-7
  =/  s6=state-6:wt  *state-6:wt
  =/  s7=state-7:wt  *state-7:wt
  %+  expect-eq  !>(%.y)
  !>(!=(bc.s6 bc.s7))
::
::  phase-2 (a): state-7's bc field uses the frozen phase-1 shape.
::  state-8's bc uses the full blockchain-constants:transact (six
::  asert-* fields). their default nouns must differ.
++  test-phase-2-state-7-bc-shape-differs-from-state-8
  =/  s7=state-7:wt  *state-7:wt
  =/  s8=state-8:wt  *state-8:wt
  %+  expect-eq  !>(%.y)
  !>(!=(bc.s7 bc.s8))
::
::  phase-2 (b): state-8 carries the full post-phase-2 blockchain-constants.
::  verify the default state-8 bc equals the default blockchain-constants:transact
::  (i.e., state-8 uses the right type, not the frozen phase-1 snapshot).
++  test-phase-2-state-8-bc-matches-transact-default
  =/  s8=state-8:wt  *state-8:wt
  %+  expect-eq  !>(*blockchain-constants:txe)
  !>(bc.s8)
::
::  fix-3b (c): the 6-to-7 upgrade re-tags and uses the phase-1 shape.
::  simulate the upgrade arm inline and verify the result carries tag %7
::  and preserves balance/active-master/keys from the old state.
++  test-fix3b-upgrade-6-to-7-produces-state-7
  =/  old=state-6:wt  *state-6:wt
  =/  upgraded=state-7:wt
    :*  %7
        balance.old
        active-master.old
        keys.old
        *blockchain-constants-v1-phase-1:wt
    ==
  ;:  weld
    %+  expect-eq  !>(%7)
    !>(-.upgraded)
    ::
    %+  expect-eq  !>(balance.old)
    !>(balance.upgraded)
  ==
::
::  phase-2 (c): the 7-to-8 upgrade re-tags and uses default
::  blockchain-constants. simulate the upgrade arm inline and verify the
::  result carries tag %8 and preserves balance/active-master/keys from
::  the old state.
++  test-phase-2-upgrade-7-to-8-produces-state-8
  =/  old=state-7:wt  *state-7:wt
  =/  upgraded=state-8:wt
    :*  %8
        balance.old
        active-master.old
        keys.old
        *blockchain-constants:txe
    ==
  ;:  weld
    %+  expect-eq  !>(%8)
    !>(-.upgraded)
    ::
    %+  expect-eq  !>(balance.old)
    !>(balance.upgraded)
  ==
--
