/=  *  /common/test
/=  *  /common/zeke
/=  zo  /common/zose
/=  hel  /tests/wallet/helpers
/=  dhel  /tests/dumb/helpers
/=  slip10  /common/slip10
/=  t  /common/tx-engine
=>
::
::  tiscom to avoid hoon-139 shadowing
=,  hel
|%
::
::  test data for create-tx timelock tests
::
++  test-recipient-sig
  ^-  sig:v0:t
  p:default-keys-1:dhel
::
++  test-gift-amount  ^-  coins:v0:t  1.288.490.189
++  test-fee-amount   ^-  coins:v0:t  0
::
++  test-names
  ^-  (list [first=@t last=@t])
  :~  ['3JzMitLaXHU7jAV7dQvgtu1V2v6GnyAgZkQdbPFvET35YiT8r2WVkVe' '2yPbWDrGRTfRKW5YCos8Jp9a8B6LBtg4JrUgtVtTTGQxk28CDEQZ7vJ']
      ['3JzMitLaXHU7jAV7dQvgtu1V2v6GnyAgZkQdbPFvET35YiT8r2WVkVe' 'CiwKyEuGHY1hMKnNkojprwRAkVgfWG8NSTunCQ1s5xdzB4JyLhX9df']
  ==
::
++  test-recipients
  ^-  (list [m=@ pks=(list @t)])
  :~  [1 ~['2qwq9dQRZfpFx8BDicghpMRnYGKZsZGxxhh9m362pzpM9aeo276pR1yHZPS41y3CW3vPKxeYM8p8fzZS8GXmDGzmNNCnVNekjrSYogqfEFMqwhHh5iCjaKPaDTwhupWqiXj6']]
      [1 ~['2qwq9dQRZfpFx8BDicghpMRnYGKZsZGxxhh9m362pzpM9aeo276pR1yHZPS41y3CW3vPKxeYM8p8fzZS8GXmDGzmNNCnVNekjrSYogqfEFMqwhHh5iCjaKPaDTwhupWqiXj6']]
  ==
::
++  test-gifts
   ^-  (list coins:v0:t)
   ~[1.288.490.189 677.589.811]
::
++  test-single-recipient
  ^-  [m=@ pks=(list @t)]
  [1 ~['2qwq9dQRZfpFx8BDicghpMRnYGKZsZGxxhh9m362pzpM9aeo276pR1yHZPS41y3CW3vPKxeYM8p8fzZS8GXmDGzmNNCnVNekjrSYogqfEFMqwhHh5iCjaKPaDTwhupWqiXj6']]
::
++  test-bad-recipients
  ^-  (list [m=@ pks=(list @t)])
  :~  [3 ~['2qwq9dQRZfpFx8BDicghpMRnYGKZsZGxxhh9m362pzpM9aeo276pR1yHZPS41y3CW3vPKxeYM8p8fzZS8GXmDGzmNNCnVNekjrSYogqfEFMqwhHh5iCjaKPaDTwhupWqiXj6']]
  ==
++  test-single-gift-amount  ^-  coins:v0:t  500.000.000
::
++  test-distributed-gift-amount  ^-  coins:v0:t  1.800.000.000
::
::  timelock helper tests
++  test-timelock-helpers
  ^-  tang
  =/  relative=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers `10 `20)
  =/  absolute=timelock-intent:v0:t
    (make-absolute-timelock-intent:timelock-helpers `100 `200)
  =/  combined=timelock-intent:v0:t
    (make-combined-timelock-intent:timelock-helpers `100 `200 `10 `20)
  =/  none=timelock-intent:v0:t
    no-timelock:timelock-helpers
  ;:  weld
    ::  test relative timelock
    %+  expect-eq
      !>(`[*timelock-range:v0:t (new:timelock-range:v0:t `10 `20)])
    !>(relative)
  ::
    ::  test absolute timelock
    %+  expect-eq
      !>(`[(new:timelock-range:v0:t `100 `200) *timelock-range:v0:t])
    !>(absolute)
  ::
    ::  test combined timelock
    %+  expect-eq
      !>(`[(new:timelock-range:v0:t `100 `200) (new:timelock-range:v0:t `10 `20)])
    !>(combined)
  ::
    ::  test no timelock
    %+  expect-eq
      !>(*timelock-intent:v0:t)
    !>(none)
  ==
--  ::timelock-test helpers
|%
::
::  derived from default-keys-1 in helpers
++  default-prv-1
  ^-  @ux
  %:  can  3
     4^0xf4d7.8fd7
     4^0x2311.48c9
     4^0x2a9f.6a96
     4^0x7d7e.ae49
     4^0x54da.f4a5
     4^0xbd2.1e25
     4^0xdcbe.5587
     4^0x52f6.1d58
     ~
  ==
::
++  default-pub-1
  ^-  @ux
  (ser-a-pt:cheetah default-a-pt-1:dhel)
::
::  derived from default-keys-2 in helpers
++  default-prv-2
  ^-  @ux
  %:  can  3
     4^0xdc5e.17b7
     4^0x5f26.324c
     4^0x8ed9.4f68
     4^0xb700.aa28
     4^0xb8c8.d96c
     4^0x7a22.545b
     4^0x2e98.4d9c
     4^0x3606.cc6f
     ~
  ==
::
++  default-pub-2
  ^-  @ux
  (ser-a-pt:cheetah default-a-pt-2:dhel)
::
++  default-cc  ^-  @ux  0x0
::
++  default-prv-coil-1  [%coil %1 [%prv default-prv-1] default-cc]
++  default-pub-coil-1  [%coil %1 [%pub default-pub-1] default-cc]
++  default-prv-coil-2  [%coil %1 [%prv default-prv-2] default-cc]
++  default-pub-coil-2  [%coil %1 [%pub default-pub-2] default-cc]
::
++  master-b58
  ^-  @t
  (crip (en:base58:wrap:zo default-pub-1))
::
++  trek-pub-master  /keys/[t/master-b58]/pub/m
++  trek-prv-master  /keys/[t/master-b58]/prv/m
++  trek-pub-child  /keys/[t/master-b58]/pub/[ud/0]
++  trek-prv-child  /keys/[t/master-b58]/prv/[ud/0]
::
++  import-list
   ^-  (list (pair trek:zo meta))
   :~  [trek-pub-master default-pub-coil-1]
       [trek-prv-master default-prv-coil-1]
       [trek-pub-child default-pub-coil-2]
       [trek-prv-child default-prv-coil-2]
   ==
::
++  import-cause  [%import-keys import-list]
::
++  test-create-tx-bad-recipient
  ::  test create-tx with a bad recipient
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-bad-recipients test-gifts]
        test-fee-amount
        ~
        no-timelock:timelock-helpers
    ==
  ~&  "create-tx-cause: {<create-tx-cause>}"
  ::
  %+  expect-fail
    |.((pok 1 create-tx-cause wal))
  ~
::
++  test-create-tx-relative-timelock
  ::  test create-tx with relative timelock constraints
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers `10 `20)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent
    ==
  ~&  "create-tx-cause: {<create-tx-cause>}"
  ::
  =/  [effs=(list effect) wal=_wal]
    (pok 1 create-tx-cause wal)
  ::
  ::  check that effects include file write and exit
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock-intent in transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::  check timelock-intent for each seed based on its purpose
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-create-tx-absolute-timelock
  ::  test create-tx with absolute timelock constraints
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-absolute-timelock-intent:timelock-helpers `100 `200)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent
    ==
  ::
  =/  [effs=(list effect) wal=_wal]
    (pok 1 create-tx-cause wal)
  ::
  ::  check that effects include file write and exit
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock-intent in transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::  check timelock-intent for each seed based on its purpose
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-create-tx-combined-timelock
  ::  test create-tx with combined timelock constraints
  ::  tests multiple parameter combinations to ensure robustness
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  ::  test with first set of combined timelock parameters
  =/  timelock-intent-1=timelock-intent:v0:t
    (make-combined-timelock-intent:timelock-helpers `100 `200 `10 `20)
  ::
  =/  create-tx-cause-1=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent-1
    ==
  ::
  =/  [effs-1=(list effect) wal-1=_wal]
    (pok 1 create-tx-cause-1 wal)
  ::
  ::  test with second set of combined timelock parameters (larger values)
  =/  timelock-intent-2=timelock-intent:v0:t
    (make-combined-timelock-intent:timelock-helpers `1.000 `5.000 `50 `150)
  ::
  =/  create-tx-cause-2=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent-2
    ==
  ::
  =/  [effs-2=(list effect) wal-2=_wal]
    (pok 2 create-tx-cause-2 wal-1)
  ::
  ::  helper function to check timelock validity for a set of effects
  ::
  |^
  =/  check-1=?  (validate-combined-timelock effs-1 timelock-intent-1)
  =/  check-2=?  (validate-combined-timelock effs-2 timelock-intent-2)
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(check-1)
  ::
    %+  expect-eq
      !>(%.y)
    !>(check-2)
  ==
  ::
  ++  validate-combined-timelock
    |=  [effs=(list effect) expected-intent=timelock-intent:v0:t]
    ^-  ?
    ::  check that effects include file write and exit
    =/  has-file-write=?
      %+  lien  effs
      |=  =effect
      ?=([%file %write @t @] effect)
    ::
    =/  has-exit=?
      %+  lien  effs
      |=  =effect
      =([%exit 0] effect)
    ::
    ?.  &(has-file-write has-exit)  %.n
    ::
    ::  verify timelock-intent in transaction
    =/  =transaction:hel
      ;;  transaction:hel
      %-  cue
      =<  contents
      ;;  [%file %write @t contents=@]
      %-  head
      %+  skim  effs
      |=  =effect
      ?=([%file %write @t jam=@] effect)
    ::
    =/  transaction-inputs=inputs:v0:t  p.transaction
    ::  get the sig of notes being spent to identify refund seeds
    =/  receive-addr=sig:v0:t  get-test-note-sig:hel
    ::  check timelock-intent for each seed based on its purpose
    =/  timelock-checks=(list ?)
      %+  turn  ~(val z-by transaction-inputs)
      |=  inp=input:v0:t
      =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
      %+  levy  seeds-list
      |=  =seed:v0:t
      ::  if this seed goes to the receive address, it's a refund and should have no timelock
      ?:  =(recipient.seed receive-addr)
        =(timelock-intent.seed *timelock-intent:v0:t)
      ::  otherwise it's a gift and should have the expected combined timelock
      ?&  =(timelock-intent.seed expected-intent)
          ::  verify the structure is what we expect for combined timelock
          ?=([~ [* *]] timelock-intent.seed)
      ==
    ::
    (levy timelock-checks |=(check=? check))
  --
::
++  test-timelock-edge-cases
  ::  test timelock edge cases with min values
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers `0 `1)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent
    ==
  ::
  =/  [effs=(list effect) wal=_wal]
    (pok 1 create-tx-cause wal)
  ::
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock-intent in transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::  check timelock-intent for each seed based on its purpose
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-timelock-large-values
  ::  test timelock with large page numbers
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-absolute-timelock-intent:timelock-helpers `1.000.000 `2.000.000)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent
    ==
  ::
  =/  [effs=(list effect) wal=_wal]
    (pok 1 create-tx-cause wal)
  ::
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock-intent in transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::  check timelock-intent for each seed based on its purpose
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-timelock-boundary-conditions
  ::  test timelock where min equals max
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers `50 `50)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent
    ==
  ::
  =/  [effs=(list effect) wal=_wal]
    (pok 1 create-tx-cause wal)
  ::
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock-intent in transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::  check timelock-intent for each seed based on its purpose
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-timelock-partial-specification
  ::  test timelock with partial specification (only min or only max)
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  ::  test with only min value set (absolute)
  =/  timelock-intent-min=timelock-intent:v0:t
    (make-absolute-timelock-intent:timelock-helpers `500 ~)
  ::
  =/  create-tx-cause-min=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent-min
    ==
  ::
  =/  [effs-min=(list effect) wal-min=_wal]
    (pok 1 create-tx-cause-min wal)
  ::
  ::  test with only max value set (relative)
  =/  timelock-intent-max=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers ~ `100)
  ::
  =/  create-tx-cause-max=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        timelock-intent-max
    ==
  ::
  =/  [effs-max=(list effect) wal-max=_wal]
    (pok 2 create-tx-cause-max wal-min)
  ::
  ::  helper function to validate partial timelock specification
  ::
  |^
  =/  check-min=?  (validate-partial-timelock effs-min timelock-intent-min)
  =/  check-max=?  (validate-partial-timelock effs-max timelock-intent-max)
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(check-min)
  ::
    %+  expect-eq
      !>(%.y)
    !>(check-max)
  ==
  ::
  ++  validate-partial-timelock
    |=  [effs=(list effect) expected-intent=timelock-intent:v0:t]
    ^-  ?
    =/  has-file-write=?
      %+  lien  effs
      |=  =effect
      ?=([%file %write @t @] effect)
    ::
    =/  has-exit=?
      %+  lien  effs
      |=  =effect
      =([%exit 0] effect)
    ::
    ?.  &(has-file-write has-exit)  %.n
    ::
    ::  verify timelock-intent in transaction
    =/  =transaction:hel
      ;;  transaction:hel
      %-  cue
      =<  contents
      ;;  [%file %write @t contents=@]
      %-  head
      %+  skim  effs
      |=  =effect
      ?=([%file %write @t jam=@] effect)
    ::
    =/  transaction-inputs=inputs:v0:t  p.transaction
    ::  get the sig of notes being spent to identify refund seeds
    =/  receive-addr=sig:v0:t  get-test-note-sig:hel
    ::  check timelock-intent for each seed based on its purpose
    =/  timelock-checks=(list ?)
      %+  turn  ~(val z-by transaction-inputs)
      |=  inp=input:v0:t
      =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
      %+  levy  seeds-list
      |=  =seed:v0:t
      ::  if this seed goes to the receive address, it's a refund and should have no timelock
      ?:  =(recipient.seed receive-addr)
        =(timelock-intent.seed *timelock-intent:v0:t)
      ::  otherwise it's a gift and should have the expected timelock
      =(timelock-intent.seed expected-intent)
    ::
    (levy timelock-checks |=(check=? check))
  --
::
++  test-create-tx-optimal-note-selection
  ::  test that create-tx doesn't create unnecessary refund outputs
  ::  when gift target can be satisfied with subset of notes
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  ::  create test with very small gift that could be satisfied by note1 alone
  ::  note1 has 1.4B coins, note2 has 800M coins from gen-spend-test-state
  =/  small-gift=coins:v0:t  100.000.000  ::  100M coins - much less than note1
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%single test-single-recipient small-gift]
        test-fee-amount
        ~
        *timelock-intent:v0:t
    ==
  ::
  =/  [effs=(list effect:hel) wal-result=_wal]
    (pok 1 create-tx-cause wal-with-state)
  ::
  ::  verify transaction succeeds
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  extract and analyze the transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::
  ::  count the number of inputs created
  =/  num-inputs=@ud  (lent ~(tap z-by transaction-inputs))
  ::
  ::  verify total gift amount is correct
  =/  all-seeds=(list seed:v0:t)
    %-  zing
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    ~(tap z-in seeds.spend.inp)
  ::
  =/  gift-seeds=(list seed:v0:t)
    %+  skim  all-seeds
    |=  =seed:v0:t
    !=(recipient.seed receive-addr)
  ::
  =/  refund-seeds=(list seed:v0:t)
    %+  skim  all-seeds
    |=  =seed:v0:t
    =(recipient.seed receive-addr)
  ::
  =/  total-gift-amount=coins:v0:t
    %+  roll  gift-seeds
    |=  [=seed:v0:t acc=coins:v0:t]
    (add acc gift.seed)
  ::
  =/  total-refund-amount=coins:v0:t
    %+  roll  refund-seeds
    |=  [=seed:v0:t acc=coins:v0:t]
    (add acc gift.seed)
  ::
  ::  ideally should only use one input since gift is small
  ::  but current implementation might use both - this test documents behavior
  =/  optimal-selection=?  (lte num-inputs 1)
  ::
  ::  total assets used (gift + refunds) should equal spent note values
  =/  total-used=coins:v0:t  (add total-gift-amount total-refund-amount)
  ::
  ::  if we're spending from both notes unnecessarily, refunds will be larger
  ::  if we're optimal, we'd spend exactly one note and have minimal refund
  =/  has-minimal-refunds=?
    ::  with 100M gift and 1.4B note1, refund should be ~1.3B
    ::  if both notes used, refunds would be much larger
    (lte total-refund-amount 1.350.000.000)
  ::
  ~&  >  "optimal note selection test results:"
  ~&  >  "num-inputs: {<num-inputs>}"
  ~&  >  "total-gift-amount: {<total-gift-amount>}"
  ~&  >  "total-refund-amount: {<total-refund-amount>}"
  ~&  >  "total-used: {<total-used>}"
  ~&  >  "optimal-selection: {<optimal-selection>}"
  ~&  >  "has-minimal-refunds: {<has-minimal-refunds>}"
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(small-gift)
    !>(total-gift-amount)
  ::
    ::  assert optimal note selection behavior
    %+  expect-eq
      !>(%.y)
    !>(optimal-selection)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-minimal-refunds)
  ::
    ::  verify we used exactly one input (optimal)
    %+  expect-eq
      !>(1)
    !>(num-inputs)
  ::
    ::  verify total used equals one note's assets (1.4B)
    %+  expect-eq
      !>(1.400.000.000)
    !>(total-used)
  ==
++  test-create-tx-null-timelock
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%multiple test-recipients test-gifts]
        test-fee-amount
        ~
        *timelock-intent:v0:t
    ==
  ::
  =/  [effs=(list effect:hel) wal-result=_wal]
    (pok 1 create-tx-cause wal-with-state)
  ::
  ::  check that effects include file write and exit
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  cue up the jammed transaction
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    ::  get the %file %write effect from the effects list
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ~&  >  "transaction: {<transaction>}"
  ::
  ::  check that the transaction has the expected timelock-intent
  =/  transaction-inputs=inputs:v0:t  p.transaction
  =/  expected-timelock-intent=timelock-intent:v0:t  *timelock-intent:v0:t
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::
  ::  verify each input has seeds with the correct timelock-intent
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed expected-timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-create-tx-single-recipient
  ::  test create-tx with single recipient mode
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%single test-single-recipient test-single-gift-amount]
        test-fee-amount
        ~
        *timelock-intent:v0:t
    ==
  ::
  =/  [effs=(list effect:hel) wal-result=_wal]
    (pok 1 create-tx-cause wal-with-state)
  ::
  ::  check that effects include file write and exit
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify the transaction structure for single recipient
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::
  ::  verify that exactly one input has a gift seed to the target recipient
  =/  gift-seeds=(list seed:v0:t)
    %-  zing
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  skim  seeds-list
    |=  =seed:v0:t
    ::  this is a gift seed if it doesn't go to receive address
    !=(recipient.seed receive-addr)
  ::
  =/  has-correct-gift=?
    ?~  gift-seeds  |
    ?&  =((lent gift-seeds) 1)
        =(gift:i.gift-seeds test-single-gift-amount)
    ==
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-correct-gift)
  ==
::
++  test-create-tx-single-recipient-with-timelock
  ::  test create-tx single recipient mode with timelock
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  =/  timelock-intent=timelock-intent:v0:t
    (make-relative-timelock-intent:timelock-helpers `5 `10)
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%single test-single-recipient test-single-gift-amount]
        test-fee-amount
        ~
        timelock-intent
    ==
  ::
  =/  [effs=(list effect:hel) wal-result=_wal]
    (pok 1 create-tx-cause wal-with-state)
  ::
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify timelock is correctly applied
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::
  ::  check timelock-intent for gift seeds (not refund seeds)
  =/  timelock-checks=(list ?)
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  levy  seeds-list
    |=  =seed:v0:t
    ::  if this seed goes to the receive address, it's a refund and should have no timelock
    ?:  =(recipient.seed receive-addr)
      =(timelock-intent.seed *timelock-intent:v0:t)
    ::  otherwise it's a gift and should have the expected timelock
    =(timelock-intent.seed timelock-intent)
  ::
  =/  all-timelocks-correct=?
    (levy timelock-checks |=(check=? check))
  ::
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(has-file-write)
  ::
    %+  expect-eq
      !>(%.y)
    !>(has-exit)
  ::
    %+  expect-eq
      !>(%.y)
    !>(all-timelocks-correct)
  ==
::
++  test-create-tx-single-recipient-insufficient-funds
  ::  test create-tx single recipient mode with insufficient funds
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  ::  try to spend more than available
  =/  large-gift=coins:v0:t  10.000.000.000  ::  much larger than test balance
  ::
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%single test-single-recipient large-gift]
        test-fee-amount
        ~
        *timelock-intent:v0:t
    ==
  ::
  =/  result
    (mule |.((pok 1 create-tx-cause wal-with-state)))
  ::
  ::  should crash with insufficient funds error
  =/  crashed=?  ?=(%| -.result)
  ::
  %+  expect-eq
    !>(%.y)
  !>(crashed)
::
++  test-create-tx-distributed-single-recipient
  ::  test create-tx where multiple notes combine for single recipient
  ::  validates that notes can collectively fund a gift larger than any single note
  ::
  =/  test-state=state:wt  gen-spend-test-state:hel
  =/  wal-with-state  (lod test-state wal)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 import-cause wal-with-state)
  ::
  ::  use a gift amount larger than any single note but achievable collectively
  =/  create-tx-cause=cause
    :*  %create-tx
        test-names
        [%single test-single-recipient test-distributed-gift-amount]
        test-fee-amount
        ~
        *timelock-intent:v0:t
    ==
  ::
  =/  [effs=(list effect:hel) wal-result=_wal]
    (pok 1 create-tx-cause wal-with-state)
  ::
  ::  verify transaction succeeds with file write and exit
  =/  has-file-write=?
    %+  lien  effs
    |=  =effect
    ?=([%file %write @t @] effect)
  ::
  =/  has-exit=?
    %+  lien  effs
    |=  =effect
    =([%exit 0] effect)
  ::
  ::  verify the transaction has correct gift amount
  =/  =transaction:hel
    ;;  transaction:hel
    %-  cue
    =<  contents
    ;;  [%file %write @t contents=@]
    %-  head
    %+  skim  effs
    |=  =effect
    ?=([%file %write @t jam=@] effect)
  ::
  =/  transaction-inputs=inputs:v0:t  p.transaction
  ::  get the sig of notes being spent to identify refund seeds
  =/  receive-addr=sig:v0:t  get-test-note-sig:hel
  ::
  ::  verify total gift amount across all gift seeds is correct
  =/  gift-seeds=(list seed:v0:t)
    %-  zing
    %+  turn  ~(val z-by transaction-inputs)
    |=  inp=input:v0:t
    =/  seeds-list=(list seed:v0:t)  ~(tap z-in seeds.spend.inp)
    %+  skim  seeds-list
    |=  =seed:v0:t
    !=(recipient.seed receive-addr)
  ::
  =/  total-gift-amount=coins:v0:t
    %+  roll  gift-seeds
    |=  [=seed:v0:t acc=coins:v0:t]
    (add acc gift.seed)
  ::
  =/  has-correct-distributed-gift=?
    ?&  !=(total-gift-amount 0)
        =(total-gift-amount test-distributed-gift-amount)
    ==
  ::  if not correct, print the gift seeds
  ~?  !has-correct-distributed-gift
    """
    incorrect distributed gift:
    gift-seeds: {<gift-seeds>}
    total-gift-amount: {<total-gift-amount>}
    test-distributed-gift-amount: {<test-distributed-gift-amount>}
    """
  ::
  =/  has-multiple-inputs=?
    (gth (lent ~(tap z-by transaction-inputs)) 1)
  ::
  ;:  weld
  ::
    %+  expect-eq
      !>([%has-exit %.y])
    !>([%has-exit has-exit])
  ::
    %+  expect-eq
      !>([%has-correct-distributed-gift %.y])
    !>([%has-correct-distributed-gift has-correct-distributed-gift])
  ::
    %+  expect-eq
      !>([%has-multiple-inputs %.y])
    !>([%has-multiple-inputs has-multiple-inputs])
  ==
--  ::spend-tests
