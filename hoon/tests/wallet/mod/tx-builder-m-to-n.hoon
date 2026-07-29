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
++  test-v1-multi-recipient-exact
  ^-  tang
  ::  twiddle the hash or rec-a to come up with a new pkh. This pkh may not correspond
  ::  to a real address, but it should be fine for testing purposes.
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =.  rec-a  rec-a(+2 0x1)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 400.000.000) (pkh-order:hel rec-b 350.000.000) (pkh-order:hel rec-c 250.000.000)]
  =/  fee=coins:t  50.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v1-note:hel rec-a 550.000.000 ~) (build-v1-note:hel rec-b 300.000.000 ~) (build-v1-note:hel rec-c 200.000.000 ~)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel notes spends 10)
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  lock-a=hash:t  (recipient-lock-root:hel rec-a)
  =/  lock-b=hash:t  (recipient-lock-root:hel rec-b)
  =/  lock-c=hash:t  (recipient-lock-root:hel rec-c)
  =/  refund-total=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(400.000.000)
    !>((sum-gifts-for-lock:hel spends lock-a))
  ::
    %+  expect-eq
      !>(350.000.000)
    !>((sum-gifts-for-lock:hel spends lock-b))
  ::
    %+  expect-eq
      !>(250.000.000)
    !>((sum-gifts-for-lock:hel spends lock-c))
  ::
    %+  expect-eq
      !>(50.000.000)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(0)
    !>(refund-total)
  ==
::
++  test-v1-multi-recipient-custom-refund
  ^-  tang
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-b 300.000.000) (pkh-order:hel rec-c 200.000.000)]
  =/  fee=coins:t  40.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v1-note:hel rec-b 320.000.000 ~) (build-v1-note:hel rec-c 280.000.000 ~)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel custom-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel [notes spends 10])
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  lock-b=hash:t  (recipient-lock-root:hel rec-b)
  =/  lock-c=hash:t  (recipient-lock-root:hel rec-c)
  =/  custom-lock=hash:t  (recipient-lock-root:hel custom-refund-pkh:hel)
  =/  refund-total=coins:t
    (sum-gifts-for-lock:hel spends custom-lock)
  =/  default-refund=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(300.000.000)
    !>((sum-gifts-for-lock:hel spends lock-b))
  ::
    %+  expect-eq
      !>(200.000.000)
    !>((sum-gifts-for-lock:hel spends lock-c))
  ::
    %+  expect-eq
      !>(40.000.000)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(60.000.000)
    !>(refund-total)
  ::
    %+  expect-eq
      !>(0)
    !>(default-refund)
  ==
::
++  test-v0-multi-recipient-with-refund
  ^-  tang
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-b 450.000.000) (pkh-order:hel rec-c 250.000.000)]
  =/  fee=coins:t  120.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v0-note:hel rec-b 350.000.000) (build-v0-note:hel rec-c 300.000.000) (build-v0-note:hel default-refund-pkh:hel 250.000.000)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel [notes spends 5])
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  lock-b=hash:t  (recipient-lock-root:hel rec-b)
  =/  lock-c=hash:t  (recipient-lock-root:hel rec-c)
  =/  refund-total=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(450.000.000)
    !>((sum-gifts-for-lock:hel spends lock-b))
  ::
    %+  expect-eq
      !>(250.000.000)
    !>((sum-gifts-for-lock:hel spends lock-c))
  ::
    %+  expect-eq
      !>(120.000.000)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(80.000.000)
    !>(refund-total)
  ==
::
++  test-v1-fanout-fee-gap-detected
  ::  note1 covers all gifts; the fee then falls on notes that, under the old
  ::  greedy gift-first split, were entirely consumed by fee (no seed) and got
  ::  dropped uncredited. Inputs (780M) cover gift (600M) + fee (150M), so
  ::  spreading the fee across the notes lets every note keep a seed and the
  ::  spend builds.
  ::
  ^-  tang
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 200.000.000) (pkh-order:hel rec-c 100.000.000)]
  =/  fee=coins:t  150.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v1-note:hel rec-a 600.000.000 ~) (build-v1-note:hel rec-b 60.000.000 ~) (build-v1-note:hel rec-c 120.000.000 ~)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel notes spends 10)
  ;:  weld
    (expect-eq !>(%.y) !>(-.validation))
    (check-conservation:hel notes spends)
    (expect-eq !>(fee) !>((roll-fees:spends:t spends)))
  ==
::
++  test-v0-fanout-fee-gap-detected
  ::  Same test as above, except for v0
  ^-  tang
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 200.000.000) (pkh-order:hel rec-c 100.000.000)]
  =/  fee=coins:t  150.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v0-note:hel rec-a 600.000.000) (build-v0-note:hel rec-b 60.000.000) (build-v0-note:hel rec-c 120.000.000)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
    %+  expect-fail
      |.((txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc))
  `"Insufficient funds to pay fee and gift"
::
++  test-v1-insufficient-fee-check
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 200.000.000) (pkh-order:hel rec-c 100.000.000)]
  =/  fee=coins:t  220.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v1-note:hel rec-a 350.000.000 ~) (build-v1-note:hel rec-b 200.000.000 ~) (build-v1-note:hel rec-c 120.000.000 ~)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
    %+  expect-fail
      |.((txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc))
  `"Insufficient funds to pay fee and gift"
::
++  test-v0-insufficient-fee-check
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 200.000.000) (pkh-order:hel rec-c 100.000.000)]
  =/  fee=coins:t  220.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v0-note:hel rec-a 350.000.000) (build-v0-note:hel rec-b 200.000.000) (build-v0-note:hel rec-c 120.000.000)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
    %+  expect-fail
      |.((txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc))
  `"Insufficient funds to pay fee and gift"
::
++  test-v1-fanout-first-note-partial-cover
  ^-  tang
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =.  rec-a  rec-a(+2 0x1)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  (hash:schnorr-pubkey:t default-a-pt-3:dhel)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 10.000.000) (pkh-order:hel rec-c 1.000.000)]
  =/  fee=coins:t  150.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v1-note:hel rec-a 250.000.000 ~) (build-v1-note:hel rec-b 200.000.000 ~) (build-v1-note:hel rec-c 100.000.000 ~)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel ~ get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel [notes spends 5])
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  lock-a=hash:t  (recipient-lock-root:hel rec-a)
  =/  lock-b=hash:t  (recipient-lock-root:hel rec-b)
  =/  lock-c=hash:t  (recipient-lock-root:hel rec-c)
  =/  refund-total=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(300.000.000)
    !>((sum-gifts-for-lock:hel spends lock-a))
  ::
    %+  expect-eq
      !>(10.000.000)
    !>((sum-gifts-for-lock:hel spends lock-b))
  ::
    %+  expect-eq
      !>(1.000.000)
    !>((sum-gifts-for-lock:hel spends lock-c))
  ::
    %+  expect-eq
      !>(150.000.000)
    !>(total-fee)
  ::
    %+  expect-eq
      !>(89.000.000)
    !>(refund-total)
  ==
::
++  test-v0-fanout-first-note-partial-cover
  ^-  tang
  =/  rec-a=hash:t  (hash:schnorr-pubkey:t default-a-pt-1:dhel)
  =/  rec-b=hash:t  (hash:schnorr-pubkey:t default-a-pt-2:dhel)
  =/  rec-c=hash:t  rec-b(+2 0x1)
  =/  orders=(list order:wt)
    ~[(pkh-order:hel rec-a 300.000.000) (pkh-order:hel rec-b 10.000.000) (pkh-order:hel rec-c 1.000.000)]
  =/  fee=coins:t  150.000.000
  =/  notes-data=(list [nname:t nnote:t])
    ~[(build-v0-note:hel rec-a 250.000.000) (build-v0-note:hel rec-b 200.000.000) (build-v0-note:hel rec-c 100.000.000)]
  =/  notes=(z-map:zo nname:t nnote:t)  (build-notes-map:hel notes-data)
  =/  names=(list nname:t)  (names-from:hel notes-data)
  =/  get-note  (get-note-from:hel notes)
  =/  spends=spends:t
    (txb:hel names orders fee default-sign-keys:hel default-refund-unit:hel get-note %.y %desc)
  =/  validation=(reason:t ~)
    (validate-with-notes:hel [notes spends 5])
  =/  total-fee=coins:t  (roll-fees:spends:t spends)
  =/  lock-a=hash:t  (recipient-lock-root:hel rec-a)
  =/  lock-b=hash:t  (recipient-lock-root:hel rec-b)
  =/  lock-c=hash:t  (recipient-lock-root:hel rec-c)
  =/  refund-total=coins:t
    (sum-gifts-for-lock:hel spends default-refund-lock-root:hel)
  ;:  weld
    %+  expect-eq
      !>(%.y)
    !>(-.validation)
  ::
    %+  expect-eq
      !>(389.000.000)
    !>((sum-gifts-for-lock:hel spends lock-a))
  ::
    %+  expect-eq
      !>(10.000.000)
    !>((sum-gifts-for-lock:hel spends lock-b))
  ::
    %+  expect-eq
      !>(1.000.000)
    !>((sum-gifts-for-lock:hel spends lock-c))
  ::
    %+  expect-eq
      !>(150.000.000)
    !>(total-fee)
  ==
--
