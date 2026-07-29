/=  wallet  /apps/wallet/wallet
/=  wt  /apps/wallet/lib/types
/=  txb-lib  /apps/wallet/lib/tx-builder
/=  wutils  /apps/wallet/lib/utils
/=  dhel  /tests/dumb/helpers
/=  bip39  /common/bip39
/=  zeke  /common/zeke
/=  zo  /common/zoon
/=  hz  /common/h-zoon
/=  zose  /common/zose
/=  *  /common/test
/=  t  /common/tx-engine
/=  *  /apps/dumbnet/lib/types
|%
::
::  structs
++  wal  (wallet *@uvI)
+$  coil  coil:wt
+$  transaction  transaction:wt
+$  cc    cc:wt
+$  meta  meta:wt
+$  effect  effect:wt
+$  cause  cause:wt
+$  input  input:wal
+$  ovum  ovum:wal
::
::  convenience functions
++  timelock-helpers
  timelock-helpers:wutils
::  state
++  state
  |=  w=_wal
  state:^inner:w
::
++  vault
  |=  w=_wal
  ~(. vault:wutils internal:outer:w)
::
++  build-ovum
  |=  cau=cause
  ^-  ovum
  =/  =input  *input
  [/poke/sys/0 input(cause cau)]
::
++  pok
  |=  [num=@ cau=cause wally=_wal]
  =^  effs=(list *)  wally
  ::  line below is necessary due to type system nonsense.
  ::  basically, the result desk-hash is type [%~ @uvI], while
  ::  the wally desk-hash is type u(@uvI)
  =<  [- +(desk-hash.outer [~ *@uvI])]
  (poke:wally num (build-ovum cau))
  =/  effects=(list effect)
    %+  murn  effs
    |=  e=*
    =/  maybe=(unit effect)
      ((soft effect) e)
    ?^  maybe  maybe
    :: try mule-ing with a ;; and file-effect
    ~&  >  "effect failed to soft: {<e>}, trying mule"
    %-  mole
    |.(;;([%file %write @t jam=@] e))
  [effects wally]
::
++  lod
  |=  [=state:wt wally=_wal]
  ^-  _wally
  ~&  >  "lod: {<state>}"
  =<  .(desk-hash.outer [~ *@uvI])
  =/  outer-state=outer-state:wal
    ;;  outer-state:wal
    [%0 [~ *@uvI] state]
  (load:wally outer-state)
::
++  entropy
  :-  32
  0x66d.ca1a.2bb7.e8a1.db28.3214.8ce9.933e.
    ea0f.3ac9.548d.7931.12d9.a95c.9407.efad
::
++  salt
  :-  16
  0xdead.beef.b1a7.c420.dead.beef.b1a7.c421
::
::  derived from seed-entropy using argon2, and then from-entropy:bip39
++  seed-phrase
  "ranch matter impact bright candy cattle quarter boost concert toilet wedding identify belt monitor honey suggest cherry cereal ribbon screen cabbage push urban glove"
::
::  OPTIMIZATION: use pre-computed seed bytes instead of computing
::  argon2 + bip39 derivation each time. This eliminates expensive
::  key derivation operations. The value below was derived from
::  entropy+salt using argon2-nockchain and bip39 to-seed.
::  Verified by test-expected-seed in keygen.hoon.
::
++  seed-byts
  ^-  byts
  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
::
::  Original computation (kept for reference):
::  :-  64
::  %+  to-seed:bip39
::    %-  from-entropy:bip39
::    :-  32
::    %+   argon2-nockchain:argon2:crypto:zose
::      entropy
::    salt
::  ""
::
++  get-test-note-sig
  ::  get the sig used by test notes for identifying refunds
  ::
  ::  OPTIMIZATION: use pre-computed keys from dumb/helpers instead of
  ::  computing EC scalar multiplication each time.
  ::  Previous implementation decoded a base58 key and did expensive EC math.
  ::
  ^-  sig:v0:t
  p:default-keys-1:dhel
::
++  gen-spend-test-state
  ::  generate wallet state with specific notes for spend testing
  ::
  ::  OPTIMIZATION: use pre-computed keys from dumb/helpers instead of
  ::  computing EC scalar multiplication and serialization each time.
  ::  This eliminates expensive crypto operations per test.
  ::
  ^-  state:wt
  =/  sig=sig:v0:t  get-test-note-sig
  ::  use pre-computed keys from dumb/helpers
  =/  sk=schnorr-seckey:v0:t  s:default-keys-1:dhel
  =/  pubkey=schnorr-pubkey:v0:t  default-a-pt-1:dhel
  =/  serialized-pubkey  (ser-a-pt:cheetah:zeke pubkey)
  ::  create source (non-coinbase)
  =/  source=source:v0:t  [*hash:v0:t %.n]
  ::  create timelock (no restrictions)
  =/  timelock=timelock:v0:t  ~
  ::  decode the specific names from the spend command
  =/  name1=nname:v0:t
    (from-b58:nname:v0:t ['3JzMitLaXHU7jAV7dQvgtu1V2v6GnyAgZkQdbPFvET35YiT8r2WVkVe' '2yPbWDrGRTfRKW5YCos8Jp9a8B6LBtg4JrUgtVtTTGQxk28CDEQZ7vJ'])
  =/  name2=nname:v0:t
    (from-b58:nname:v0:t ['3JzMitLaXHU7jAV7dQvgtu1V2v6GnyAgZkQdbPFvET35YiT8r2WVkVe' 'CiwKyEuGHY1hMKnNkojprwRAkVgfWG8NSTunCQ1s5xdzB4JyLhX9df'])
  ::  create notes with sufficient assets to cover the gifts
  =/  note1=nnote:v0:t
    :*
      :*  version=%0
          origin-page=0
          timelock
      ==
      name=name1
      sig
      source
      assets=1.400.000.000  ::  enough to cover gift 1288490189 + margin
    ==
  =/  note2=nnote:v0:t
    :*
      :*  version=%0
          origin-page=0
          timelock
      ==
      name=name2
      sig
      source
      assets=800.000.000   ::  enough to cover gift 677589811 + margin
    ==
  ::  create balance with both notes
  =/  test-balance=(z-map nname:v0:t nnote:v0:t)
    %-  ~(gas z-by *(z-map nname:v0:t nnote:v0:t))
    ~[[name1 note1] [name2 note2]]
  ::  create master key coils
  =/  master-pubkey-coil=coil  [%0 [%pub ;;(@ux serialized-pubkey)] 0x0]
  =/  master-privkey-coil=coil  [%0 [%prv (t8-to-atom:belt-schnorr:cheetah:zeke sk)] 0x0]
  ::  create keys state with both pub and prv keys
  =|  keys-state=keys:wt
  =/  master-b58=@t  (crip (en:base58:wrap:zose serialized-pubkey))
  =/  priv-trek=trek:zose  /keys/[t/master-b58]/prv/m
  =/  pub-trek=trek:zose   /keys/[t/master-b58]/pub/m
  =.  keys-state
    %+  ~(put of:zose keys-state)  priv-trek
    [%coil master-privkey-coil]
  =.  keys-state
    %+  ~(put of:zose keys-state)  pub-trek
    [%coil master-pubkey-coil]
  ::  return complete state
  %*  .  *state:wt
    balance  [*page-number:v0:t *hash:v0:t test-balance]
    keys     keys-state
    active-master   (some master-pubkey-coil)
  ==
::
::  tx builder + spend helpers
::
++  signer-pubkey-1
  ^-  schnorr-pubkey:t
  default-a-pt-1:dhel
::
++  signer-seckey-1
  ^-  schnorr-seckey:t
  s:default-keys-1:dhel
::
++  signer-pubkey-2
  ^-  schnorr-pubkey:t
  default-a-pt-2:dhel
::
++  signer-seckey-2
  ^-  schnorr-seckey:t
  s:default-keys-2:dhel
::
++  signer-pubkey-3
  ^-  schnorr-pubkey:t
  default-a-pt-3:dhel
::
++  signer-seckey-3
  ^-  schnorr-seckey:t
  s:default-keys-3:dhel
::
++  default-signer-pubkey
  ^-  schnorr-pubkey:t
  signer-pubkey-1
::
++  signer-seckey
  ^-  schnorr-seckey:t
  signer-seckey-1
::
++  default-sign-keys
  ^-  (list schnorr-seckey:t)
  ~[signer-seckey]
::
++  default-signer-sig
  ^-  sig:t
  (new:sig:t default-signer-pubkey)
::
++  txb
  |=  $:  names=(list nname:t)
          orders=(list order:wt)
          fee=coins:t
          sign-keys=(list schnorr-seckey:t)
          refund-pkh=(unit hash:t)
          get-note=$-(nname:t nnote:t)
          include-data=?
          note-selection=selection-strategy:wt
      ==
  ^-  spends:v1:t
  =/  =transaction:wt
    %:  build:txb-lib
      names
      orders
      fee
      %.n
      sign-keys
      refund-pkh
      get-note
      ~
      include-data
      note-selection
      0
    ==
  (apply:witness-data:wt witness-data.transaction spends.transaction)
::
++  recipient-lock-root
  |=  recipient=hash:t
  ^-  hash:t
  =/  lock=lock:t
    [%pkh [m=1 (z-silt:zo ~[recipient])]]~
  (hash:lock:t lock)
::
++  default-refund-pkh
  ^-  hash:t
  (hash:schnorr-pubkey:t default-signer-pubkey)
::
++  default-refund-unit
  ^-  (unit hash:t)
  [~ default-refund-pkh]
::
++  default-refund-lock-root
  ^-  hash:t
  (recipient-lock-root default-refund-pkh)
::
++  custom-refund-pkh
  ^-  hash:t
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-signer-pubkey)
  rec-a(+2 0xf)
::
++  custom-refund-unit
  ^-  (unit hash:t)
  [~ custom-refund-pkh]
::
++  pkh-order
  |=  [recipient=hash:t gift=coins:t]
  ^-  order:wt
  [%pkh recipient gift]
::
++  gather-seeds
  |=  sp=spend:v1:t
  ^-  (list seed:v1:t)
  ?-  -.sp
    %0  ~(tap z-in:zo seeds.+.sp)
    %1  ~(tap z-in:zo seeds.+.sp)
  ==
::
++  sum-gifts-for-lock
  |=  [sps=spends:t target=hash:t]
  ^-  coins:t
  %+  roll  ~(tap z-by:zo sps)
  |=  [[=nname:t sp=spend-v1:t] acc=coins:t]
  %+  add  acc
  %+  roll  (gather-seeds sp)
  |=  [sed=seed-v1:t sum=coins:t]
  ?.  =(lock-root.sed target)
    sum
  (add sum gift.sed)
::
++  check-conservation
  |=  [notes=(z-map:zo nname:t nnote:t) =spends:t]
  ^-  tang
  =/  total-inputs=coins:t
    %+  roll  ~(val z-by:zo notes)
    |=  [=nnote:t sum=coins:t]
    (add sum assets.nnote)
  =/  total-outputs=coins:t
    %+  roll  ~(tap z-by:zo spends)
    |=  [[=nname:t sp=spend-v1:t] sum=coins:t]
    %+  add  sum
    %+  roll  (gather-seeds sp)
    |=  [sed=seed-v1:t acc=coins:t]
    (add acc gift.sed)
  =/  total-fees=coins:t  (roll-fees:spends:t spends)
  =/  total-accounted=coins:t  (add total-outputs total-fees)
  %+  expect-eq
    !>(total-inputs)
  !>(total-accounted)
::
++  build-v0-note
  |=  [source-hash=hash:t assets=coins:t]
  ^-  [name=nname:t note=nnote:v0:t]
  =/  tim=timelock:t  *timelock:t
  =/  src=source:t  [source-hash %.n]
  =/  name=nname:t  (new:nname:t default-signer-sig src tim)
  =/  note=nnote:v0:t
    %*  .  *nnote:v0:t
      version      %0
      origin-page  1
      timelock     tim
    ::
      name    name
      sig     default-signer-sig
      source  src
      assets  assets
    ==
  [name note]
::
++  build-v1-note
  |=  $:  source-hash=hash:t
          assets=coins:t
          signer=(unit schnorr-pubkey:t)
      ==
  ^-  [name=nname:t note=nnote-1:v1:t]
  (build-v1-note-at-origin source-hash assets signer 0)
::
++  build-v1-note-at-origin
  |=  $:  source-hash=hash:t
          assets=coins:t
          signer=(unit schnorr-pubkey:t)
          origin-page=page-number:t
      ==
  ^-  [name=nname:t note=nnote-1:v1:t]
  =/  use-signer=schnorr-pubkey:t
    ?~  signer  default-signer-pubkey
    u.signer
  =/  [lock-root=hash:t sc=spend-condition:t *]
    (make-pkh-lock:v1:dhel 1 ~[use-signer])
  =/  nd=(z-map:zo @tas *)
    %-  ~(put z-by:zo *(z-map:zo @tas *))
    [%lock `lock-data:wt`[%0 sc]]
  =/  name=nname:t  (new-v1:nname:t lock-root [source-hash %.n])
  =/  note=nnote-1:v1:t
    %*  .  *nnote-1:v1:t
      version      %1
      origin-page  origin-page
      name         name
      note-data    nd
      assets       assets
    ==
  [name note]
::
++  build-v0-coinbase-note
  |=  [parent-hash=hash:t assets=coins:t]
  ^-  [name=nname:t note=nnote:t]
  =/  tim=timelock:t  coinbase-timelock:coinbase:v0:t
  =/  src=source:t  [parent-hash %.y]
  =/  name=nname:t  (new:nname:t default-signer-sig src tim)
  =/  note=nnote:t
    %*  .  *nnote:v0:t
      version      %0
      origin-page  1
      timelock     tim
    ::
      name    name
      sig     default-signer-sig
      source  src
      assets  assets
    ==
  [name note]
::
++  build-v1-coinbase-note
  |=  [parent-hash=hash:t assets=coins:t]
  ^-  [name=nname:t note=nnote:t]
  =/  [lock-root=hash:t sc=spend-condition:t *]
    (make-coinbase-lock:v1:dhel 1 ~[default-signer-pubkey])
  =/  name=nname:t  (new-v1:nname:t lock-root [parent-hash %.y])
  =/  note=nnote:t
    %*  .  *nnote-1:v1:t
      version      %1
      origin-page  1
      name         name
      assets       assets
    ==
  [name note]
::
++  build-multisig-note
  |=  $:  source-hash=hash:t
          assets=coins:t
          m=@
          pubkey-hashes=(z-set:zo hash:t)
      ==
  ^-  [name=nname:t note=nnote:t]
  =/  lock=lock:t
    [%pkh [m (z-silt:zo ~(tap z-in:zo pubkey-hashes))]]~
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  nd=(z-map:zo @tas *)
    %-  ~(put z-by:zo *(z-map:zo @tas *))
    [%lock `lock-data:wt`[%0 lock]]
  =/  name=nname:t  (new-v1:nname:t lock-root [source-hash %.n])
  =/  note=nnote:t
    %*  .  *nnote-1:v1:t
      version      %1
      origin-page  0
      name         name
      note-data    nd
      assets       assets
    ==
  [name note]
::
++  build-notes-map
  |=  pairs=(list [name=nname:t note=nnote:t])
  ^-  (z-map:zo nname:t nnote:t)
  %-  ~(gas z-by:zo *(z-map:zo nname:t nnote:t))
  %+  turn  pairs
  |=  [=nname:t =nnote:t]
  [nname nnote]
::
++  names-from
  |=  pairs=(list [name=nname:t note=nnote:t])
  ^-  (list nname:t)
  %+  turn  pairs
  |=  [=nname:t *]
  nname
::
++  get-note-from
  |=  notes=(z-map:zo nname:t nnote:t)
  ^=  get
  |=  nam=nname:t
  =/  maybe=(unit nnote:t)  (~(get z-by:zo notes) nam)
  ?~  maybe  !!
  u.maybe
::
++  validate-with-notes
  |=  [notes=(z-map:zo nname:t nnote:t) =spends:t max=@]
  ^-  (reason:t ~)
  =/  bc  *blockchain-constants:t
  %-  validate-with-context:spends:t
  [(zh-molt:hz notes) spends max max-size.data.bc bythos-phase.bc]
::
++  multisig-lock-root
  |=  [m=@ participants=(list hash:t)]
  ^-  hash:t
  =/  lock=lock:t
    [%pkh [m (z-silt:zo participants)]]~
  (hash:lock:t lock)
::
++  multisig-order
  |=  [threshold=@ participants=(list hash:t) gift=coins:t]
  ^-  order:wt
  [%multisig threshold=threshold participants=participants gift=gift]
::
++  multisig-lock-root-from-set
  |=  [m=@ pubkey-hashes=(z-set:zo hash:t)]
  ^-  hash:t
  (multisig-lock-root m ~(tap z-in:zo pubkey-hashes))
::
++  txb-multisig
  |=  $:  names=(list nname:t)
          gift=coins:t
          fee=coins:t
          m=@
          pubkey-hashes=(z-set:zo hash:t)
          sign-keys=(list schnorr-seckey:t)
          refund-pkh=(unit hash:t)
          get-note=$-(nname:t nnote:t)
          note-selection=selection-strategy:wt
      ==
  ^-  spends:v1:t
  =/  order=order:wt
    (multisig-order m ~(tap z-in:zo pubkey-hashes) gift)
  (txb names ~[order] fee sign-keys refund-pkh get-note %.y note-selection)
::
++  source-lock-root
  |=  signer=schnorr-pubkey:t
  ^-  hash:t
  =/  pkh=hash:t  (hash:schnorr-pubkey:t signer)
  =/  lok=lock:t  [%pkh [m=1 (z-silt:zo ~[pkh])]]~
  (hash:lock:t lok)
::
++  collect-seeds
  |=  sps=spends:t
  ^-  (list seed:v1:t)
  %+  roll  ~(tap z-by:zo sps)
  |=  [[=nname:t sp=spend-v1:t] acc=(list seed:v1:t)]
  (weld (gather-seeds sp) acc)
::
++  find-seed-by-lock
  |=  [seeds=(list seed:v1:t) target-lock=hash:t]
  ^-  (unit seed:v1:t)
  |-
  ?~  seeds  ~
  =/  sed=seed:v1:t  i.seeds
  ?:  =(lock-root.sed target-lock)
    (some sed)
  $(seeds t.seeds)
::
++  build-pubkey-hashes-set
  |=  pubkeys=(list schnorr-pubkey:t)
  ^-  (z-set:zo hash:t)
  %-  z-silt:zo
  %+  turn  pubkeys
  |=  pk=schnorr-pubkey:t
  (hash:schnorr-pubkey:t pk)
::
--
