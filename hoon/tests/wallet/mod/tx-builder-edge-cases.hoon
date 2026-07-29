/=  *  /common/test
/=  *  /common/zeke
/=  zo  /common/zoon
/=  *  /common/zose
/=  dhel  /tests/dumb/helpers
/=  wt  /apps/wallet/lib/types
/=  hel  /tests/wallet/helpers
/=  t  /common/tx-engine
|%
::
++  test-v0-second-note-pure-refund
  ::  first note satisfies gift+fee, second note becomes pure refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  note1-assets=coins:t  (add gift fee)
  =/  note2-assets=coins:t  200.000.000
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note1-assets)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 note2-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  sp2=spend:v1:t  (~(got z-by:zo spends) name2)
  ?>  ?=(%0 -.sp2)
  =/  spend2=spend-0:v1:t  +.sp2
  =/  seeds2=(list seed-v1:t)  ~(tap z-in:zo seeds.spend2)
  =/  refund-root=hash:t  default-refund-lock-root:hel
  =/  refund-seeds2=(list seed-v1:t)
    %+  skim  seeds2
    |=  sed=seed-v1:t
    =(lock-root.sed refund-root)
  =/  gift-seeds2=(list seed-v1:t)
    %+  skim  seeds2
    |=  sed=seed-v1:t
    =(lock-root.sed (recipient-lock-root:hel recipient-hash))
  ;:  weld
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(note2-assets)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(0)
    !>(fee.spend2)
  ::
    %+  expect-eq
      !>(~)
    !>(gift-seeds2)
  ::
    %+  expect-eq
      !>(seeds2)
    !>(refund-seeds2)
  ==
::
++  test-v0-second-note-fee-with-small-refund
  ::  first note satisfies gift, second used for fee with small refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  note1-assets=coins:t  gift
  =/  note2-assets=coins:t  (add fee 1.000.000)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note1-assets)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 note2-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  sp2=spend:v1:t  (~(got z-by:zo spends) name2)
  ?>  ?=(%0 -.sp2)
  =/  spend2=spend-0:v1:t  +.sp2
  =/  seeds2=(list seed-v1:t)  ~(tap z-in:zo seeds.spend2)
  ;:  weld
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(1.000.000)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(fee)
    !>(fee.spend2)
  ::
    %+  expect-eq
      !>(1)
    !>(~(wyt z-in:zo seeds.spend2))
  ==
::
++  test-v0-note-selection-descending
  ::  descending strategy spends largest note first, smaller note untouched
  ::
  ^-  tang
  =/  source-small=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source-large=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  note-small=coins:t  200.000.000
  =/  note-large=coins:t  800.000.000
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  [name-small=nname:t note-small-obj=nnote:t]
    (build-v0-note:hel source-small note-small)
  =/  [name-large=nname:t note-large-obj=nnote:t]
    (build-v0-note:hel source-large note-large)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name-small note-small-obj] [name-large note-large-obj]])
  =/  names=(list nname:t)  ~[name-small name-large]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  spent-small=?  (~(has z-by:zo spends) name-small)
  =/  sp-small=spend:v1:t  (~(got z-by:zo spends) name-small)
  =/  sp-large=spend:v1:t  (~(got z-by:zo spends) name-large)
  ?>  ?=(%0 -.sp-small)
  ?>  ?=(%0 -.sp-large)
  =/  spend-small=spend-0:v1:t  +.sp-small
  =/  spend-large=spend-0:v1:t  +.sp-large
  =/  expected-refund=coins:t
    (sub (add note-small note-large) (add gift fee))
  ;:  weld
    (expect !>(-.validation))
  ::
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(spent-small)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(expected-refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(fee.spend-large)
  ::
    %+  expect-eq
      !>(0)
    !>(fee.spend-small)
  ==
::
++  test-v0-note-selection-ascending
  ::  ascending strategy spends smallest note first, larger note untouched
  ::
  ^-  tang
  =/  source-small=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  source-large=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  note-small=coins:t  350.000.000
  =/  note-large=coins:t  900.000.000
  =/  gift=coins:t  250.000.000
  =/  fee=coins:t  25.000.000
  =/  [name-small=nname:t note-small-obj=nnote:t]
    (build-v0-note:hel source-small note-small)
  =/  [name-large=nname:t note-large-obj=nnote:t]
    (build-v0-note:hel source-large note-large)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name-small note-small-obj] [name-large note-large-obj]])
  =/  names=(list nname:t)  ~[name-small name-large]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %asc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  spent-large=?  (~(has z-by:zo spends) name-large)
  =/  sp-small=spend:v1:t  (~(got z-by:zo spends) name-small)
  =/  sp-large=spend:v1:t  (~(got z-by:zo spends) name-large)
  ?>  ?=(%0 -.sp-small)
  =/  spend-small=spend-0:v1:t  +.sp-small
  ?>  ?=(%0 -.sp-large)
  =/  spend-large=spend-0:v1:t  +.sp-large
  =/  expected-refund=coins:t  (sub (add note-small note-large) (add gift fee))
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(spent-large)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(expected-refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(fee.spend-small)
  ::
    %+  expect-eq
      !>(0)
    !>(fee.spend-large)
  ==
::
++  test-v1-second-note-pure-refund
  ::  v1 version: first note satisfies gift+fee, second is refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  700.000.000
  =/  fee=coins:t  75.000.000
  =/  note1-assets=coins:t  (add gift fee)
  =/  note2-assets=coins:t  300.000.000
  =/  [name1=nname:t note1=nnote:t]
    (build-v1-note:hel source1 note1-assets ~)
  =/  [name2=nname:t note2=nnote:t]
    (build-v1-note:hel source2 note2-assets ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  sp2=spend:v1:t  (~(got z-by:zo spends) name2)
  ?>  ?=(%1 -.sp2)
  =/  spend2=spend-1:v1:t  +.sp2
  =/  seeds2=(list seed-v1:t)  ~(tap z-in:zo seeds.spend2)
  =/  gift-seeds2=(list seed-v1:t)
    %+  skim  seeds2
    |=  sed=seed-v1:t
    =(lock-root.sed (recipient-lock-root:hel recipient-hash))
  =/  refund-total2=coins:t
    %+  roll  seeds2
    |=  [sed=seed-v1:t acc=coins:t]
    ?:  =(lock-root.sed (recipient-lock-root:hel recipient-hash))
      acc
    (add acc gift.sed)
  ;:  weld
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::  note2 carries no recipient gift (its value is fee + change)
    %+  expect-eq
      !>(~)
    !>(gift-seeds2)
  ::
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(fee)
    !>((roll-fees:spends:t spends))
  ==
::
++  test-v1-second-note-fee-with-small-refund
  ::  v1 version: first satisfies gift, second pays fee with small refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  800.000.000
  =/  fee=coins:t  100.000.000
  =/  note1-assets=coins:t  gift
  =/  note2-assets=coins:t  (add fee 5.000.000)
  =/  [name1=nname:t note1=nnote:t]
    (build-v1-note:hel source1 note1-assets ~)
  =/  [name2=nname:t note2=nnote:t]
    (build-v1-note:hel source2 note2-assets ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  entry-count=@  (lent ~(tap z-by:zo spends))
  =/  sp2=spend:v1:t  (~(got z-by:zo spends) name2)
  ?>  ?=(%1 -.sp2)
  =/  spend2=spend-1:v1:t  +.sp2
  =/  seeds2-count=@  ~(wyt z-in:zo seeds.spend2)
  ;:  weld
    %+  expect-eq
      !>(2)
    !>(entry-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    (check-conservation:hel notes spends)
  ==
::
++  test-v0-three-notes-complex-split
  ::  gift spans note1+note2, fee from note2+note3, refund from note3
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  source3=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  gift=coins:t  1.000.000.000
  =/  fee=coins:t  150.000.000
  =/  [name1=nname:t note1=nnote:t]  (build-v0-note:hel source1 600.000.000)
  =/  [name2=nname:t note2=nnote:t]  (build-v0-note:hel source2 500.000.000)
  =/  [name3=nname:t note3=nnote:t]  (build-v0-note:hel source3 300.000.000)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2] [name3 note3]])
  =/  names=(list nname:t)  ~[name1 name2 name3]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  total-assets=coins:t
    ;:  add
      assets.note1
      assets.note2
      assets.note3
    ==
  =/  expected-refund=coins:t  (sub total-assets (add gift fee))
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(expected-refund)
    !>(total-refund)
  ==
::
++  test-v1-exact-match-no-waste
  ::  total assets exactly equal gift + fee, no refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  700.000.000
  =/  fee=coins:t  50.000.000
  =/  total-needed=coins:t  (add gift fee)
  =/  [name1=nname:t note1=nnote:t]
    (build-v1-note:hel source1 400.000.000 ~)
  =/  [name2=nname:t note2=nnote:t]
    (build-v1-note:hel source2 350.000.000 ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  all-seeds=(list seed-v1:t)
    %-  zing
    %+  turn  ~(tap z-by:zo spends)
    |=  [=nname:t sp=spend-v1:t]
    (gather-seeds:hel sp)
  =/  non-gift-seeds=(list seed-v1:t)
    %+  skim  all-seeds
    |=  sed=seed-v1:t
    !=(lock-root.sed (recipient-lock-root:hel recipient-hash))
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(~)
    !>(non-gift-seeds)
  ==
::
++  test-v1-pkh-note-without-data-spendable
  ::  ensure a simple %pkh note lacking note-data can still be spent
  ::
  ^-  tang
  =/  source=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  400.000.000
  =/  fee=coins:t  40.000.000
  =/  note-assets=coins:t  (add gift fee)
  =/  [name=nname:t note=nnote-1:v1:t]
    (build-v1-note:hel source note-assets ~)
  ~&  name+name
  =/  stripped=nnote-1:v1:t  note(note-data ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name stripped]])
  =/  names=(list nname:t)  ~[name]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  ;:  weld
    %+  expect-eq
      !>(~)
    !>(note-data.stripped)
  ::
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    (check-conservation:hel notes spends)
  ==
::
++  test-v0-original-bug-scenario
  ::  recreates the original bug: note1 satisfies gift+partial fee,
  ::  note2 should provide remaining fee + large refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  total-inputs=coins:t  597.563.467
  =/  gift=coins:t  519.143.883
  =/  fee=coins:t  2.883.584
  =/  expected-refund=coins:t  (sub total-inputs (add gift fee))
  ::  note1 is sized to cover gift plus partial fee
  =/  note1-assets=coins:t  522.027.467
  =/  note2-assets=coins:t  (sub total-inputs note1-assets)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note1-assets)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 note2-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  total-out=coins:t
    ;:  add
      total-gift
      total-refund
      total-fee
    ==
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(expected-refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(total-inputs)
    !>(total-out)
  ==

 ++  test-v1-second-note-pure-fee
    ::  v1: note1 == gift, note2 == fee exactly (inputs == gift + fee, zero
    ::  margin). The fee is spread across both notes so each retains a seed and
    ::  the spend builds. Previously this failed spuriously because the second
    ::  note, entirely consumed by fee, was dropped uncredited (leaving the fee
    ::  unpaid).
    ::
    ^-  tang
    =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
    =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
    =/  gift=coins:t  700.000.000
    =/  fee=coins:t  75.000.000
    =/  note1-assets=coins:t  700.000.000
    =/  note2-assets=coins:t  75.000.000
    =/  [name1=nname:t note1=nnote:t]
      (build-v1-note:hel source1 note1-assets ~)
    =/  [name2=nname:t note2=nnote:t]
      (build-v1-note:hel source2 note2-assets ~)
    =/  notes=(z-map:zo nname:t nnote:t)
      (build-notes-map:hel ~[[name1 note1] [name2 note2]])
    =/  names=(list nname:t)  ~[name1 name2]
    =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
    =/  order=order:wt  (pkh-order:hel recipient-hash gift)
    =/  orders=(list order:wt)  ~[order]
    =/  get-note  (get-note-from:hel notes)
    =/  spends=spends:t
      (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
    =/  validation=(reason:t ~)
      (validate-with-notes:hel [notes spends 10])
    =/  total-gift=coins:t
      (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
    =/  total-fees=coins:t  (roll-fees:spends:t spends)
    ;:  weld
      (expect-eq !>(%.y) !>(-.validation))
      (check-conservation:hel notes spends)
      (expect-eq !>(fee) !>(total-fees))
      (expect-eq !>(gift) !>(total-gift))
    ==
::
  ++  test-v0-second-note-pure-fee
     ::  v0 version: first note satisfies gift, second note perfectly satisfies fee
     ::
     ^-  tang
     =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
     =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
     =/  gift=coins:t  700.000.000
     =/  fee=coins:t  75.000.000
     =/  note1-assets=coins:t  700.000.000
     =/  note2-assets=coins:t  75.000.000
     =/  [name1=nname:t note1=nnote:t]
       (build-v0-note:hel source1 note1-assets)
     =/  [name2=nname:t note2=nnote:t]
       (build-v0-note:hel source2 note2-assets)
     =/  notes=(z-map:zo nname:t nnote:t)
       (build-notes-map:hel ~[[name1 note1] [name2 note2]])
     =/  names=(list nname:t)  ~[name1 name2]
     =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
     =/  order=order:wt  (pkh-order:hel recipient-hash gift)
     =/  orders=(list order:wt)  ~[order]
     =/  get-note  (get-note-from:hel notes)
    %+  expect-fail
      |.((txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc))
    `"Insufficient funds to pay fee and gift"
  ::
++  test-v0-spend-into-multisig
  ::  spend a v0 note into a multisig output
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  refund=coins:t  150.000.000
  =/  note-assets=coins:t  :(add gift fee refund)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1]])
  =/  names=(list nname:t)  ~[name1]
  =/  participants=(list hash:t)
    ~[(hash:schnorr-pubkey:t default-a-pt-2:dhel) (hash:schnorr-pubkey:t default-a-pt-3:dhel)]
  =/  order=order:wt  (multisig-order:hel 2 participants gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  target-lock=hash:t  (multisig-lock-root:hel 2 participants)
  =/  total-gift=coins:t  (sum-gifts-for-lock:hel spends target-lock)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ==
::
++  test-v0-two-notes-into-multisig
  ::  spend multiple v0 notes into a multisig output
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  750.000.000
  =/  fee=coins:t  60.000.000
  =/  refund=coins:t  140.000.000
  =/  total-need=coins:t  :(add gift fee refund)
  =/  note1-assets=coins:t  500.000.000
  =/  note2-assets=coins:t  (sub total-need note1-assets)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note1-assets)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 note2-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  participants=(list hash:t)
    ~[(hash:schnorr-pubkey:t default-a-pt-2:dhel) (hash:schnorr-pubkey:t default-a-pt-3:dhel)]
  =/  order=order:wt  (multisig-order:hel 2 participants gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  target-lock=hash:t  (multisig-lock-root:hel 2 participants)
  =/  total-gift=coins:t  (sum-gifts-for-lock:hel spends target-lock)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ==
::
++  test-v0-degenerate-single-key-spendable
  ::  ensure a v0 note with m > |pubkeys| but a single key remains spendable
  ::
  ^-  tang
  =/  source=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  400.000.000
  =/  fee=coins:t  40.000.000
  =/  refund=coins:t  60.000.000
  =/  total-assets=coins:t  :(add gift fee refund)
  =/  [name=nname:t note=nnote:v0:t]
    (build-v0-note:hel source total-assets)
  ::  insert degenerate sig
  =.  sig.note  [m=2 pubkeys=pubkeys.sig.note]
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name note]])
  =/  names=(list nname:t)  ~[name]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  =/  recipient-lock=hash:t  (recipient-lock-root:hel recipient-hash)
  =/  total-gift=coins:t  (sum-gifts-for-lock:hel spends recipient-lock)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  pubkey-count=@  ~(wyt z-in:zo pubkeys.sig.note)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(refund)
    !>(total-refund)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(2)
    !>(m.sig.note)
  ::
    %+  expect-eq
      !>(1)
    !>(pubkey-count)
  ==
::
  ++  test-zero-gift-order-rejected
    ^-  tang
    =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
    =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
    =/  orders=(list order:wt)
      ~[(pkh-order:hel rec-a 0) (pkh-order:hel rec-b 100.000.000)]
    =/  fee=coins:t  50.000.000
    =/  notes-data=(list [nname:t nnote:t])
      ~[(build-v1-note:hel rec-b 200.000.000 ~)]
    =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
    =/  names=(list nname:t)  ~(tap z-in:zo ~(key z-by:zo notes))
    =/  get-note  (get-note-from:hel notes)
    %+  expect-fail
      |.((txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc))
    `"One or more orders are invalid. Reason: %gift-cannot-be-zero"
--
