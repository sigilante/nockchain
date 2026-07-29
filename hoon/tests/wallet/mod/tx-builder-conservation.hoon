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
++  test-v0-three-notes-middle-pure-refund
  ::  note1: gift, note2: pure refund, note3: fee
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  source3=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  100.000.000
  =/  middle-refund=coins:t  200.000.000
  =/  [name1=nname:t note1=nnote:t]  (build-v0-note:hel source1 gift)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 middle-refund)
  =/  [name3=nname:t note3=nnote:t]  (build-v0-note:hel source3 fee)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2] [name3 note3]])
  =/  names=(list nname:t)  ~[name1 name2 name3]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel (get-note-from:hel notes) %.y %desc)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(middle-refund)
    !>(total-refund)
  ==
::
++  test-v0-four-notes-complex-allocation
  ::  4 notes with overlapping gift/fee contributions + refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  source3=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  source4=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  800.000.000
  =/  fee=coins:t  150.000.000
  =/  [name1=nname:t note1=nnote:t]  (build-v0-note:hel source1 400.000.000)
  =/  [name2=nname:t note2=nnote:t]  (build-v0-note:hel source2 350.000.000)
  =/  [name3=nname:t note3=nnote:t]  (build-v0-note:hel source3 300.000.000)
  =/  [name4=nname:t note4=nnote:t]  (build-v0-note:hel source4 250.000.000)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2] [name3 note3] [name4 note4]])
  =/  names=(list nname:t)  ~[name1 name2 name3 name4]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel (get-note-from:hel notes) %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 5]
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ==
::
++  test-v0-minimal-refund-one-nick
  ::  total assets = gift + fee + 1, verify 1 nick refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  note-assets=coins:t  (add (add gift fee) 1)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 note-assets)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1]])
  =/  names=(list nname:t)  ~[name1]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel (get-note-from:hel notes) %.y %desc)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(1)
    !>(total-refund)
  ==
::
++  test-v1-large-fee-requires-multiple-notes
  ::  fee distributed across multiple notes with refunds
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  source3=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  gift=coins:t  400.000.000
  =/  fee=coins:t  200.000.000
  =/  [name1=nname:t note1=nnote:t]  (build-v1-note:hel source1 300.000.000 ~)
  =/  [name2=nname:t note2=nnote:t]  (build-v1-note:hel source2 250.000.000 ~)
  =/  [name3=nname:t note3=nnote:t]  (build-v1-note:hel source3 200.000.000 ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2] [name3 note3]])
  =/  names=(list nname:t)  ~[name1 name2 name3]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ (get-note-from:hel notes) %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  =/  total-fees=coins:t  (roll-fees:spends:t spends)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(fee)
    !>(total-fees)
  ==
::
++  test-v1-many-small-notes
  ::  10 small notes, verify all are used correctly
  ::
  ^-  tang
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  note-size=coins:t  60.000.000
  =/  notes-data=(list [nname:t nnote:t])
    %+  turn  (gulf 0 9)
    |=  i=@
    =/  source=hash:t
      (hash:schnorr-pubkey:t default-a-pt-2:dhel)
    (build-v1-note:hel source note-size ~)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel notes-data)
  =/  names=(list nname:t)
    (turn notes-data |=([n=nname:t *] n))
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ (get-note-from:hel notes) %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ==
::
++  test-v0-tiny-note-becomes-refund
  ::  tiny note still creates refund seed
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  gift=coins:t  500.000.000
  =/  fee=coins:t  50.000.000
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 (add gift fee))
  =/  tiny-amount=coins:t  100
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 tiny-amount)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel (get-note-from:hel notes) %.y %desc)
  =/  spend-count=@  (lent ~(tap z-by:zo spends))
  =/  note2-spent=?  (~(has z-by:zo spends) name2)
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(2)
    !>(spend-count)
  ::
    %+  expect-eq
      !>(%.y)
    !>(note2-spent)
  ::
    %+  expect-eq
      !>(tiny-amount)
    !>(total-refund)
  ==
::
++  test-v1-asymmetric-large-small-notes
  ::  one huge note + many small notes with sufficient refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  800.000.000
  =/  fee=coins:t  80.000.000
  =/  [name1=nname:t note1=nnote:t]
    (build-v1-note:hel source1 900.000.000 ~)
  =/  small-notes=(list [nname:t nnote:t])
    %+  turn  (gulf 0 4)
    |=  i=@
    =/  unique-source=hash:t
      [i 0x1 0x2 0x3 0x4]
    (build-v1-note:hel unique-source 80.000.000 ~)
  =/  all-notes=(list [nname:t nnote:t])
    [^-([nname:t nnote:t] [name1 note1]) small-notes]
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel all-notes)
  =/  names=(list nname:t)
    (turn all-notes |=([n=nname:t *] n))
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ (get-note-from:hel notes) %.y %desc)
  =/  validation=(reason:t ~)
    %-  validate-with-notes:hel
  [notes spends 10]
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    (check-conservation:hel notes spends)
  ==
::
++  test-v0-most-value-becomes-refund
  ::  small gift/fee, most value becomes refund
  ::
  ^-  tang
  =/  source1=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  source2=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  [name1=nname:t note1=nnote:t]
    (build-v0-note:hel source1 300.000.000)
  =/  [name2=nname:t note2=nnote:t]
    (build-v0-note:hel source2 200.000.000)
  =/  notes=(z-map:zo nname:t nnote:t)
    (build-notes-map:hel ~[[name1 note1] [name2 note2]])
  =/  names=(list nname:t)  ~[name1 name2]
  =/  recipient-hash=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  gift=coins:t  10.000.000
  =/  order=order:wt  (pkh-order:hel recipient-hash gift)
  =/  orders=(list order:wt)  ~[order]
  =/  fee=coins:t  5.000.000
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel (get-note-from:hel notes) %.y %desc)
  =/  total-gift=coins:t
    (sum-gifts-for-lock:hel spends (recipient-lock-root:hel recipient-hash))
  =/  total-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  =/  expected-refund=coins:t
    (sub (add assets.note1 assets.note2) (add gift fee))
  ;:  weld
    (check-conservation:hel notes spends)
  ::
    %+  expect-eq
      !>(gift)
    !>(total-gift)
  ::
    %+  expect-eq
      !>(expected-refund)
    !>(total-refund)
  ==
--
