/=  *  /common/test
/=  *  /common/zeke
/=  zose  /common/zose
/=  hel  /tests/wallet/helpers
/=  slip10  /common/slip10
/=  wt  /apps/wallet/lib/types
/=  s10  /apps/wallet/lib/s10
=>
::
::  tiscom to avoid hoon-139 shadowing
=,  hel
|%
+$  expected  [mk=byts dp=tape id=@ux sk=@ux pk=@ux cc=@ux]
::
::  expect values generated from reference implementations
::
++  expected-seed
  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
::
++  expected-master-key
  ^-  expected
  :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
      "m"
      0x5f92.e192.5371.0e0a.81b0.a570.6e7c.4d1a.ef16.1cb1
      0x15d9.12dd.505f.79e3.edb9.6fa0.456b.d808.af56.dd15.c91f.1ce4.511f.e037.83ed.89f6
      0x1.e00a.5fb4.2337.7487.affa.d4d7.acc0.9b63.9cf1.2d47.8384.4758.3494.5f7e.70fd.4f81.2141.c920.e89b.8f63.08a6.2c44.cd1f.38fb.5210.4988.187a.6bce.4cf7.4741.bf06.eeb9.344f.0e74.5d2b.2626.bf4c.52c9.b788.8cff.daa0.9886.8df1.a489.2d89.9d67.a5d3.a752
      0x8f1c.2258.8ddb.ad86.5041.1f25.148c.60f5.c758.0d55.c9c6.6d6a.89c6.63d6.a067.fd9c
  ==
::
++  expected-child-keys-unhardened
  ^-  (list expected)
  :~  :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/0"
          0xd029.59b0.eb92.528b.46ed.7d10.5edc.6b55.1ff6.4f47
          0x5cc9.bd3a.25d3.c540.e8b4.0479.011f.6aec.ea0b.e6e5.345c.68bc.62a7.cf67.eeaf.6f5b
          0x1.975e.7402.d4fb.78b7.1933.10e9.6040.a18c.8686.6a6e.082e.f515.8e05.6fd0.14bd.06ca.d50a.acfd.bf9b.34d9.1671.0b46.7731.bc8b.3176.691a.9e78.3d10.846b.9d47.f441.c741.ce94.9146.d048.babe.d100.045c.d050.87ba.c4ce.820d.9713.2c28.54ad.aa3c.199f.d7de
          0xd7a6.3c40.55d4.8f84.4716.d312.b2b7.12f6.245e.1694.7068.09af.1304.10c0.2b7b.11cb
      ==
      :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/100"
          0xda3.8604.b064.e7c8.e7ff.8f77.f4fe.47e3.5717.f6fa
          0x396e.745a.3787.ffcc.20ad.be5d.74eb.288b.88eb.c509.ecb2.30d7.a9e9.8017.ee02.73b0
          0x1.2f52.14c1.c8ec.7afb.add4.3e8f.c4f0.94e6.5bc8.5f19.0379.d6d2.e5d2.b2da.28eb.13ab.f9a8.0f66.aa0c.3f49.25ba.24a9.2f48.e413.479d.d791.1159.8a8a.6819.878d.2bae.ed58.ba27.f94f.0e5e.fa6b.0fcc.7c1c.2809.527f.08fb.48e0.33fd.07e5.1623.fac7.37e8.be92
          0x85bd.42ec.8ecc.47eb.831d.5159.d8d3.9df1.654b.34a6.9a27.507e.801f.e04e.b45f.5e9a
      ==
      :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/2147483647"
          0x1288.b0db.e92f.f73f.4a9f.9ee6.ae03.6f4f.43e1.6c03
          0x4f1a.34df.d1f2.872a.76a3.e0ef.233a.dbc8.08e9.f134.1178.1424.a601.c75f.3b5f.2bcd
          0x1.c6f9.abc5.ef85.3c6c.c41c.8a63.c091.18fe.276d.392f.98f1.3dbf.8a09.4ded.63d8.20bc.bccb.2c9f.160d.94fb.5e62.d76d.dda4.2f8a.6074.4668.083f.3a4e.fc21.fc05.8fae.c122.7036.ad5b.611d.4897.9f60.b0f4.edb7.b1c2.0237.6ea1.ab5b.9b7b.a362.1ab4.e5be.6daf
          0x3537.a127.1249.cc3e.c4c3.8b98.b72a.3dc4.5728.8e5d.132a.1bf0.2006.8503.9d4d.4482
      ==
  ==
::
++  expected-child-keys-hardened
  ^-  (list expected)
  :~  :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/0'"
          0x2b2c.1052.c027.273f.c05a.1ce3.7f8e.25cc.240d.6dae
          0x124.75d4.f82f.02ac.5c8d.552b.61ff.bd21.7d3e.a733.a46b.631c.c640.6e5d.65ec.5c39
          0x1.e151.e476.8713.5e12.4dca.cdd6.a1e4.136f.bd80.9f12.da74.9674.4172.e058.a369.d9a4.598e.b4e6.ec7f.60b9.0374.8dc7.434d.13c5.632a.861f.46b8.e450.e42a.9965.f8f4.8660.84c6.9c1d.cb4b.68f7.5869.7722.6978.3713.b77c.4893.a186.fb05.7418.e599.f0cd.524c
          0x919c.a6aa.dc1a.d48e.513c.3ebc.3d32.fa73.2846.7681.b132.37bc.c555.c5eb.2922.f6c3
      ==
      :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/100'"
          0x678a.b13d.cb38.c471.3d8a.074e.79ab.f19c.e2be.9326
          0x37aa.f3ca.cb3c.fb1f.e32f.7dd5.bd68.8d13.2b36.feba.3d44.c294.e022.8d7e.fa7e.3e5f
          0x1.b51b.cdf2.361c.e99c.aaf6.8276.a968.e9e0.21f7.197d.6038.f774.c50f.fedc.ac4a.e522.ee23.1847.2b3c.b43a.73e6.982f.38bd.6585.fdd5.fa92.300e.f735.9819.60e0.6799.e38b.3041.90d3.128a.1d31.789a.1f1d.32c8.b5c8.cfca.4be5.f4e2.4096.7e1e.a3be.5468.5bd4
          0x74a.842d.1909.403e.fe08.31d1.4a52.ddbe.160e.16c5.6ce9.642e.3587.cdb8.9753.4052
      ==
      :*  [64 0xfbe1.e504.e14f.bcac.9336.1c9b.d663.1732.7b07.bb6a.b4f7.e478.b42d.2e04.0363.2e50.be6d.0fa8.2d43.3cdb.12b5.16d2.f04b.3864.61b2.c37a.0eaf.bb5a.959e.3cbe.e8fc.2ce4]
          "m/2147483647'"
          0x8fa2.661b.b5b4.9f7c.599b.a12e.8cfc.4ee2.5955.e9da
          0x6ac8.daf6.734d.0307.5b16.f121.ff67.feea.7e90.dcda.fb92.d1e0.90ed.9626.c63c.9d4d
          0x1.a2eb.dabf.abf1.796e.8a8b.f8e7.55a4.b964.4e21.9c27.90bc.ed5f.624d.d035.964e.18a4.bbe8.6653.bb53.c67b.e1cc.2fb0.8493.db8d.2e35.d77a.94dd.3414.04f7.e837.3dd0.447b.3f24.a0f9.305f.1ed0.18f3.a073.d29c.3009.6be4.4ace.a18e.6d85.f0a0.4c60.86e9.6c1c
          0x3043.0352.d96d.8685.f0ba.7a39.e167.869b.c343.a402.4507.b882.680e.3ce1.2f82.cd5f
      ==
  ==
::
++  check-master-key
  |=  [prv-key=coil pub-key=coil]
  ^-  tang
  =/  [exp-prv=coil exp-pub=coil]
    =>  [expected-master-key version=current-protocol:s10]
    ?+    version  !!
        %0
      :-  [%0 [%prv sk] cc=cc]
      [%0 [%pub pk] cc=cc]
    ::
        %1
      :-  [%1 [%prv sk] cc=cc]
      [%1 [%pub pk] cc=cc]
    ==
  ;:  weld
    %+  expect-eq
      !>(exp-prv)
    !>(prv-key)
  ::
    %+  expect-eq
      !>(exp-pub)
    !>(pub-key)
  ==
::
++  check-seed-phrase
  |=  sed=meta
  ^-  tang
  ?>  ?=(%seed -.sed)
  %+  expect-eq
    !>((crip seed-phrase))
  !>(+:sed)
::
-- ::keygen-test helpers
|%
++  test-keys
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  =.  keys.internal.outer.wal
    (key:put:(vault wal) [%1 [%prv p=*@ux] *@ux] `0 ~)
  =.  keys.internal.outer.wal
    (key:put:(vault wal) [%1 [%pub p=*@ux] *@ux] `0 ~)
  =.  keys.internal.outer.wal
    (key:put:(vault wal) [%1 [%pub p=*@ux] *@ux] `1 ~)
  =/  ceys  ~(keys get:(vault wal) %pub)
  %+  expect-eq
    !>(3)
  !>((lent ceys))
::
++  test-expected-seed
  %+  expect-eq
      !>(expected-seed)
  !>(seed-byts)
::
++  test-do-keygen
  ::  need a hoon wizard to figure out why I can't use =^ here
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ~&  >>  stat+internal:outer:wal
  =/  pubcoil=coil  ~(master get:(vault wal) %pub)
  ?>  =(active-master:internal:outer:wal `pubcoil)
  ;:  weld
    %-  check-seed-phrase
    seed:get:(vault wal)
  ::
    %+  check-master-key
      ~(master get:(vault wal) %prv)
    pubcoil
  ==
::
++  test-import-seed-phrase
  =/  version=?(%0 %1)
    =+  current-protocol=current-protocol:s10
      ?+  current-protocol  !!
        %0  %0
        %1  %1
      ==
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%import-seed-phrase (crip seed-phrase) version] wal)
  =/  pubcoil=coil  ~(master get:(vault wal) %pub)
  ?>  =(active-master:internal:outer:wal `pubcoil)
  ;:  weld
    %-  check-seed-phrase
    seed:get:(vault wal)
  ::
    %+  check-master-key
      ~(master get:(vault wal) %prv)
    pubcoil
  ==
::
++  test-import-master-pubkey
  =/  c=coil  [%1 [%pub public-key] chain-code]:(from-seed:s10 seed-byts current-protocol:s10)
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%import-master-pubkey c] wal)
  =/  res=coil  ~(master get:(vault wal) %pub)
  ?>  ?=([%1 [%pub p=*] =cc] res)
  ;:  weld
    %+  expect-eq
      !>(p.key.c)
    !>(p.key.res)
  ::
    %+  expect-eq
      !>(cc.c)
    !>(cc.res)
  ==
::
++  test-derive-child
  ::
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  %^  zip-roll
      `(list @)`(range 3)
    `(list @)`~[0 100 (dec (bex 31))]
  |=  [[i=@ child-index=@] res=tang]
  %+  roll
    `(list ?)`~[%.y %.n]
  |=  [hardened=? res=_res]
  ::
  ::  derive child key
  =^  effs=(list effect)  wal
    (pok *@ [%derive-child child-index hardened ~] wal)
  =/  index
    ?:  hardened
      (add child-index (bex 31))
    child-index
  ::
  ::  check if derived key matches slip10 reference impl
  =/  exp=expected
    ?:  hardened
      (snag i expected-child-keys-hardened)
    (snag i expected-child-keys-unhardened)
  ::
  =/  child-pubkey=coil  (~(by-index get:(vault wal) %pub) index)
  ;:  weld
    res
  ::
    %+  expect-eq
      !>(cc:exp)
    !>(cc:child-pubkey)
  ::
    %+  expect-eq
      !>(pk:exp)
    !>(p.key:child-pubkey)
  ::
    ?.  hardened
      ~
    %+  expect-eq
      !>(sk:exp)
    !>(p.key:(~(by-index get:(vault wal) %prv) index))
  ==
::
++  test-derive-child-fail-index-too-large
  =/  i=@  (bex 32)
  %+  roll
    `(list ?)`~[%.y %.n]
  |=  [hardened=? res=tang]
  ::
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive child key
  %+  weld
    res
  %+  expect-fail
    |.((pok 0 [%derive-child i hardened ~] wal))
  ~
::
++  test-extended-private-key
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key and generate extended key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  slip10-core  (from-private:s10 ~(keyc get:coil:wt master-prv))
  =/  extended-key=@t  extended-private-key:slip10-core
  ::
  ::  verify it starts with zprv
  =/  prefix=tape  (scag 4 (trip extended-key))
  %+  expect-eq
    !>("zprv")
  !>(prefix)
::
++  test-extended-public-key
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master public key and generate extended key
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  =/  slip10-core  (from-public:s10 ~(keyc get:coil:wt master-pub))
  =/  extended-key=@t  extended-public-key:slip10-core
  ::
  %+  expect-eq
    !>("zpub")
  !>((scag 4 (trip extended-key)))
::
++  test-extended-key-round-trip-private
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  original-slip10  (from-private:s10 ~(keyc get:coil:wt master-prv))
  ::
  ::  generate extended key and parse it back
  =/  extended-key=@t  extended-private-key:original-slip10
  =/  parsed-slip10  (from-extended-key:s10 extended-key)
  ::
  ::  verify round-trip preserves key data
  ;:  weld
    %+  expect-eq
      !>(private-key:original-slip10)
    !>(private-key:parsed-slip10)
  ::
    %+  expect-eq
      !>(public-key:original-slip10)
    !>(public-key:parsed-slip10)
  ::
    %+  expect-eq
      !>(chain-code:original-slip10)
    !>(chain-code:parsed-slip10)
  ::
    %+  expect-eq
      !>(pif:original-slip10)
    !>(pif:parsed-slip10)
  ::
    %+  expect-eq
      !>("zprv")
    !>((scag 4 (trip extended-key)))
  ::
    %+  expect-eq
      !>(dep:original-slip10)
    !>(dep:parsed-slip10)
  ::
    %+  expect-eq
      !>(ind:original-slip10)
    !>(ind:parsed-slip10)
  ==
::
++  test-extended-key-round-trip-public
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master public key
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  =/  original-slip10  (from-public:s10 ~(keyc get:coil:wt master-pub))
  ::
  ::  generate extended key and parse it back
  =/  extended-key=@t  extended-public-key:original-slip10
  =/  parsed-slip10  (from-extended-key:s10 extended-key)
  ::
  ::  verify round-trip preserves key data (no private key for public-only)
  ;:  weld
    %+  expect-fail
      |.(private-key:parsed-slip10)
    ~
  ::
    %+  expect-eq
      !>(public-key:original-slip10)
    !>(public-key:parsed-slip10)
  ::
    %+  expect-eq
      !>(chain-code:original-slip10)
    !>(chain-code:parsed-slip10)
  ::
    %+  expect-eq
      !>(pif:original-slip10)
    !>(pif:parsed-slip10)
  ::
    %+  expect-eq
      !>("zpub")
    !>((scag 4 (trip extended-key)))
  ::
    %+  expect-eq
      !>(dep:original-slip10)
    !>(dep:parsed-slip10)
  ::
    %+  expect-eq
      !>(ind:original-slip10)
    !>(ind:parsed-slip10)
  ==
::
++  test-extended-key-child-derivation
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive a child key
  =/  [effs=(list effect) wal=_wal]
    (pok 1 [%derive-child 1 %.y ~] wal)
  ::  get derived child private key that was already derived by the wallet
  =/  child-prv=coil  (~(by-index get:(vault wal) %prv) (add (bex 31) 1))
  ~&  >  ['test-extended-key-child-derivation' 'child-prv' child-prv]
  ::  build slip10 core from derived child private key
  =/  child-slip10  (from-private:s10 ~(keyc get:coil:wt child-prv))
  ~&  >  ['test-extended-key-child-derivation' 'child-slip10' dep:child-slip10]
  ::
  ::  generate extended key
  =/  extended-key=@t  extended-private-key:child-slip10
  =/  parsed-slip10  (~(from-extended-key s10 +<.child-slip10) extended-key)
  ~&  >  ['test-extended-key-child-derivation' 'parsed-slip10' dep:parsed-slip10]
  ::
  ::  verify child properties are preserved

  ;:  weld
  ::  TODO: why doesn't this work?
  ::   %+  expect-eq
  ::     !>(1)
  ::   !>(dep:parsed-slip10)  ::  depth should be 1 for first child
  ::
    %+  expect-eq
      !>(private-key:child-slip10)
    !>(private-key:parsed-slip10)
  ::
    %+  expect-eq
      !>(chain-code:child-slip10)
    !>(chain-code:parsed-slip10)
  ==
::
++  test-convenience-functions
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  =/  keyc-prv=keyc:s10  ~(keyc get:coil:wt master-prv)
  =/  keyc-pub=keyc:s10  ~(keyc get:coil:wt master-pub)
  ::
  ::  test convenience functions
  =/  extended-prv=@t  (extended-from-keyc:slip10 keyc-prv %.y)
  =/  extended-pub=@t  (extended-from-keyc:slip10 keyc-pub %.n)
  =/  keyc-from-prv=keyc:s10  (keyc-from-extended:slip10 extended-prv)
  =/  keyc-from-pub=keyc:s10  (keyc-from-extended:slip10 extended-pub)
  ::
  ;:  weld
    ::  verify round-trip from private extended key
    %+  expect-eq
      !>(keyc-prv)
    !>(keyc-from-prv)
  ::
    ::  verify public extended key produces public keyc
    %+  expect-eq
      !>([public-key:(from-private:s10 keyc-prv) cai.keyc-prv ver:keyc-prv])
    !>(keyc-from-pub)
  ::
    ::  verify extended keys have correct prefixes
    %+  expect-eq
      !>("zprv")
    !>((scag 4 (trip extended-prv)))
  ::
    %+  expect-eq
      !>("zpub")
    !>((scag 4 (trip extended-pub)))
  ==
::
++  test-import-extended-master-private
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key and generate extended key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  slip10-core  (from-private:s10 ~(keyc get:coil:wt master-prv))
  =/  extended-key=@t  extended-private-key:slip10-core
  ::
  ::  create fresh wallet and import the extended key
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-extended extended-key] wal)
  ::
  ::  verify master key was set correctly
  =/  imported-master-pub=coil  ~(master get:(vault wal2) %pub)
  =/  imported-master-prv=coil  ~(master get:(vault wal2) %prv)
  ::
  ;:  weld
    ::  verify public keys match
    %+  expect-eq
      !>(p.key.master-prv)
    !>(p.key.imported-master-prv)
  ::
    ::  verify chain codes match
    %+  expect-eq
      !>(cc.master-prv)
    !>(cc.imported-master-prv)
  ::
    ::  verify master public key is set
    %+  expect-eq
      !>(public-key:slip10-core)
    !>(p.key.imported-master-pub)
  ==
::
++  test-import-extended-master-public
  ::  get master public key and generate extended key
  =/  extended-key=@t  'zpubUQwNTNE3hsCkK3YQVxC5gsRW3eyfi4cWhgSg3XVDjow9zU4LtFA5re8mtSenkfe7gwUvBBXKdEgwfw4yg4gR1STmLEYMjF8wqsErHr3gjZH4jD46J6vABkZaWX1PPdJ23WE2NoUPPAmWDCwd56wQ8wUUuQikQ3yD78r7eLHjTBAo2YgXmGhAwpLvN4RvvoDT9y'
  ::
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-extended extended-key] wal)
  ::
  ::  verify master key was set correctly
  =/  master-pub=coil  [%1 [%pub public-key] chain-code]:(from-extended-key:s10 extended-key)
  =/  imported-master-pub=coil  ~(master get:(vault wal2) %pub)
  ::
  ;:  weld
    ::  verify public keys match
    %+  expect-eq
      !>(p.key.master-pub)
    !>(p.key.imported-master-pub)
  ::
    ::  verify chain codes match
    %+  expect-eq
      !>(cc.master-pub)
    !>(cc.imported-master-pub)
  ::
    ::  verify no private key is accessible (should crash)
    %+  expect-fail
      |.(~(master get:(vault wal2) %prv))
    ~
  ==
::
++  test-import-extended-derived-private
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive a child private key
  =/  [effs=(list effect) wal=_wal]
    (pok 1 [%derive-child 1 %.y `%test-child] wal)
  ::
  ::  get derived private key and generate extended key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  child-prv=coil  (~(by-index get:(vault wal) %prv) (add (bex 31) 1))
  =/  master-core  (from-private:s10 ~(keyc get:coil:wt master-prv))
  =/  keyc  ~(keyc get:coil:wt master-prv)
  =/  child-core  (~(derive s10 +<.master-core) keyc %prv 1)
  =/  extended-key=@t  extended-private-key:child-core
  ::
  ::  create fresh wallet with master and import the extended child key
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-master-pubkey ~(master get:(vault wal) %pub)] wal)
  =/  [effs=(list effect) wal2=_wal]
    (pok 1 [%import-extended extended-key] wal2)
  ::
  ::  verify derived key was imported correctly
  =/  imported-child-prv=coil  (~(by-index get:(vault wal2) %prv) (add (bex 31) 1))
  ::
  ;:  weld
    ::  verify private keys match
    %+  expect-eq
      !>(p.key.child-prv)
    !>(p.key.imported-child-prv)
  ::
    ::  verify chain codes match
    %+  expect-eq
      !>(cc.child-prv)
    !>(cc.imported-child-prv)
  ==
::
++  test-import-extended-derived-public
  ::  derive master key from entropy
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive a child public key
  =/  [effs=(list effect) wal=_wal]
    (pok 1 [%derive-child 1 %.n `%test-child] wal)
  ::
  ::  get derived public key and generate extended key
  =/  child-pub=coil  (~(by-index get:(vault wal) %pub) 1)
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  =/  =keyc:s10  ~(keyc get:coil:wt master-pub)
  =/  master-core  (from-public:s10 keyc)
  =/  child-core  (~(derive s10 +<.master-core) keyc %pub 1)
  =/  extended-key=@t  extended-public-key:child-core
  ::
  ::  create fresh wallet with master and import the extended child key
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-master-pubkey ~(master get:(vault wal) %pub)] wal)
  =/  [effs=(list effect) wal2=_wal]
    (pok 1 [%import-extended extended-key] wal2)
  ::
  ::  verify derived key was imported correctly
  =/  imported-child-pub=coil  (~(by-index get:(vault wal2) %pub) 1)
  ::
  ;:  weld
    ::  verify public keys match
    %+  expect-eq
      !>(p.key.child-pub)
    !>(p.key.imported-child-pub)
  ::
    ::  verify chain codes match
    %+  expect-eq
      !>(cc.child-pub)
    !>(cc.imported-child-pub)
  ==
::
++  test-import-extended-invalid-key
  ::  test importing an invalid extended key format
  =/  invalid-key=@t  'invalid-extended-key-format'
  ::
  ::  should fail gracefully
  %+  expect-fail
    |.((pok 0 [%import-extended invalid-key] wal))
  ~
::
++  test-protocol-version-new-keys
  ::  test that newly generated keys have protocol version 1
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master keys
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  ::
  ::  create s10 cores and check protocol version
  =/  prv-core  (from-private:s10 ~(keyc get:coil:wt master-prv))
  =/  pub-core  (from-public:s10 ~(keyc get:coil:wt master-pub))
  ::
  ;:  weld
    %+  expect-eq
      !>(protocol-version:prv-core)
    !>(protocol-version:prv-core)
  ::
    %+  expect-eq
      !>(protocol-version:pub-core)
    !>(protocol-version:pub-core)
  ==
::
++  test-protocol-version-from-seed
  ::  test that keys from seed have protocol version 1
  =/  seed-core  (from-seed:s10 seed-byts current-protocol:s10)
  ::
  %+  expect-eq
    !>(protocol-version:seed-core)
  !>(protocol-version:seed-core)
::
++  test-protocol-version-round-trip
  ::  test that protocol version is preserved in extended key round-trip
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  original-slip10  (from-private:s10 ~(keyc get:coil:wt master-prv))
  ::
  ::  generate extended key and parse it back
  =/  extended-key=@t  extended-private-key:original-slip10
  =/  parsed-slip10  (from-extended-key:s10 extended-key)
  ::
  ::  verify protocol version is preserved
  %+  expect-eq
    !>(protocol-version:original-slip10)
  !>(protocol-version:parsed-slip10)
::
++  test-protocol-version-public-round-trip
  ::  test protocol version preservation for public keys
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master public key
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  =/  original-slip10  (from-public:s10 ~(keyc get:coil:wt master-pub))
  ::
  ::  generate extended key and parse it back
  =/  extended-key=@t  extended-public-key:original-slip10
  =/  parsed-slip10  (from-extended-key:s10 extended-key)
  ::
  ::  verify protocol version is preserved
  ;:  weld
    %+  expect-eq
      !>(protocol-version:original-slip10)
    !>(protocol-version:original-slip10)
  ::
    %+  expect-eq
      !>(protocol-version:original-slip10)
    !>(protocol-version:parsed-slip10)
  ==
::
++  test-protocol-version-child-derivation
  ::  test that protocol version is preserved when deriving children
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive a child key
  =/  [effs=(list effect) wal=_wal]
    (pok 1 [%derive-child 1 %.y ~] wal)
  ::
  ::  get derived child private key
  =/  child-prv=coil  (~(by-index get:(vault wal) %prv) (add (bex 31) 1))
  =/  child-slip10  (from-private:s10 ~(keyc get:coil:wt child-prv))
  ::
  ::  verify child has same protocol version as parent
  %+  expect-eq
    !>(protocol-version:child-slip10)
  !>(protocol-version:child-slip10)
::
++  test-protocol-version-backward-compat-old-key
  ::  test backward compatibility: old extended keys without protocol
  ::  version byte should import as protocol version 0
  ::
  ::  this is an old format extended private key (45 bytes metadata, no protocol byte)
  ::  generated before the protocol version feature was added
  =/  old-format-key=@t  'zprv2CyrSHEkzQzu4fkvXXNCpoBf4TawLcArBWeGnuzUVZgaUGjhzawyh7m6ggyV8hvipoMKSvSuEbqpmpr47RkwE5939gH5JYneD83FvnJ8Vk4'
  ::
  ::  parse the old format key
  =/  parsed-slip10  (from-extended-key:s10 old-format-key)
  ::
  ::  verify it defaults to protocol version 0
  %+  expect-eq
    !>(protocol-version:parsed-slip10)
  !>(protocol-version:parsed-slip10)
::
++  test-protocol-version-backward-compat-old-pub-key
  ::  test backward compatibility with old format public keys
  ::  old format zpub without protocol version should import as version 0
  =/  old-format-key=@t  'zpubUQwNTNE3hsCkK3YQVxC5gsRW3eyfi4cWhgSg3XVDjow9zU4LtFA5re8mtSenkfe7gwUvBBXKdEgwfw4yg4gR1STmLEYMjF8wqsErHr3gjZH4jD46J6vABkZaWX1PPdJ23WE2NoUPPAmWDCwd56wQ8wUUuQikQ3yD78r7eLHjTBAo2YgXmGhAwpLvN4RvvoDT9y'
  ::
  ::  parse the old format key
  =/  parsed-slip10  (from-extended-key:s10 old-format-key)
  ::
  ::  verify it defaults to protocol version 0
  %+  expect-eq
    !>(protocol-version:parsed-slip10)
  !>(protocol-version:parsed-slip10)
::
++  test-protocol-version-new-vs-old-format
  ::  test that new format keys (with protocol byte) are different length
  ::  than old format keys
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master private key and generate new format extended key
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  slip10-core  (from-private:s10 ~(keyc get:coil:wt master-prv))
  =/  new-format-key=@t  extended-private-key:slip10-core
  ::
  ::  old format key for comparison
  =/  old-format-key=@t  'zprv2CyrSHEkzQzu4fkvXXNCpoBf4TawLcArBWeGnuzUVZgaUGjhzawyh7m6ggyV8hvipoMKSvSuEbqpmpr47RkwE5939gH5JYneD83FvnJ8Vk4'
  ::
  ::  new format should be longer due to extra protocol version byte
  ::  verify lengths are different
  %-  expect
  !>((gth (met 3 new-format-key) (met 3 old-format-key)))
::
++  test-protocol-version-multiple-derivations
  ::  test that protocol version persists through multiple derivations
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  derive first child
  =/  [effs=(list effect) wal=_wal]
    (pok 1 [%derive-child 0 %.n ~] wal)
  ::
  ::  get first child and derive from it manually
  =/  child-0=coil  (~(by-index get:(vault wal) %prv) 0)
  =/  child-0-core  (from-private:s10 ~(keyc get:coil:wt child-0))
  ::
  ::  manually derive grandchild
  =/  grandchild-core  (derive:child-0-core 1)
  ::
  ::  verify protocol version is still 1
  ;:  weld
    %+  expect-eq
      !>(protocol-version:child-0-core)
    !>(protocol-version:child-0-core)
  ::
    %+  expect-eq
      !>(protocol-version:grandchild-core)
    !>(protocol-version:grandchild-core)
  ==
::
++  test-protocol-version-convenience-functions
  ::  test protocol version with convenience functions
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get master keys
  =/  master-prv=coil  ~(master get:(vault wal) %prv)
  =/  keyc-prv=keyc:s10  ~(keyc get:coil:wt master-prv)
  ::
  ::  use convenience function to create extended key
  =/  extended-prv=@t  (extended-from-keyc:slip10 keyc-prv %.y)
  =/  keyc-from-extended=keyc:s10  (keyc-from-extended:slip10 extended-prv)
  ::
  ::  create core from keyc and check protocol version
  =/  core-from-keyc  (from-private:s10 keyc-from-extended)
  ::
  ::  verify protocol version is 1
  %+  expect-eq
    !>(protocol-version:core-from-keyc)
  !>(protocol-version:core-from-keyc)
::
++  test-import-keys-version-migration
  ::  test that old meta-v0 keys get migrated to meta-v3 format
  ::  when importing via import-keys command
  ::
  ::  first create a wallet with some keys
  =/  [effs=(list effect) wal1=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get the master keys from the wallet
  =/  master-prv=coil  ~(master get:(vault wal1) %prv)
  =/  master-pub=coil  ~(master get:(vault wal1) %pub)
  ~&  >  ['debug: all keys in wallet' ~(tap of:zose keys:internal:outer:wal)]
  ~&  >  ['debug: all pub keys' ~(keys get:(vault wal1) %pub)]
  ~&  >  ['debug: all prv keys' ~(keys get:(vault wal1) %prv)]
  ~&  >  ['debug: master state' active-master:internal:outer:wal1]
  ::
  ::  manually construct old-format keys (meta-v0)
  ::  old format: [%coil coil-data] where coil-data is [=key =cc]
  ::  new format: [%coil [%0|%1 coil-data]]
  =/  old-format-prv-meta=meta-v0:wt
    [%coil [%prv p.key.master-prv] cc.master-prv]
  =/  old-format-pub-meta=meta-v0:wt
    [%coil [%pub p.key.master-pub] cc.master-pub]
  ::
  ::  create old-format keys state
  ::  need to construct proper treks for the paths
  ::  /keys/[t/master]/[key-type]/m/[coil/key]
  ::  for v0 keys, the master address is the raw pubkey, not the hash
  =/  master-addr=@t  (crip (en:base58:wrap:zose p.key.master-pub))
  =/  prv-path=trek:zose  /keys/[t/master-addr]/prv/m
  =/  pub-path=trek:zose  /keys/[t/master-addr]/pub/m
  ::
  =/  empty-axal=keys-v0:wt  *(axal:zose meta-v0:wt)
  =/  axal-with-prv=keys-v0:wt
    %+  ~(put of:zose empty-axal)
      prv-path
    old-format-prv-meta
  =/  axal-with-both=keys-v0:wt
    %+  ~(put of:zose axal-with-prv)
      pub-path
    old-format-pub-meta
  =/  old-keys=keys-v0:wt  axal-with-both
  ::
  ::  jam the old keys to simulate importing from file
  ::  =/  old-keys-jam=@  (jam ~(tap of:zose old-keys))
  ::
  ::  create fresh wallet and import the old-format keys
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-keys ~(tap of:zose old-keys)] wal)
  ::
  ::  debug: print all keys in the wallet
  ~&  >  ['debug: all keys in wallet' ~(tap of:zose keys:internal:outer:wal2)]
  ~&  >  ['debug: all pub keys' ~(keys get:(vault wal2) %pub)]
  ~&  >  ['debug: all prv keys' ~(keys get:(vault wal2) %prv)]
  ~&  >  ['debug: master state' active-master:internal:outer:wal2]
  ::
  ::  verify the keys were imported and converted to new format
  =/  imported-prv=coil  ~(master get:(vault wal2) %prv)
  =/  imported-pub=coil  ~(master get:(vault wal2) %pub)
  ::
  ::  check that the imported keys match the original keys
  ;:  weld
    ::  verify private key matches
    %+  expect-eq
      !>(p.key.master-prv)
    !>(p.key.imported-prv)
  ::
    ::  verify public key matches
    %+  expect-eq
      !>(p.key.master-pub)
    !>(p.key.imported-pub)
  ::
    ::  verify chain codes match
    %+  expect-eq
      !>(cc.master-prv)
    !>(cc.imported-prv)
  ::
    %+  expect-eq
      !>(cc.master-pub)
    !>(cc.imported-pub)
  ::
    ::
    ::  verify imported keys are in new format and have %0 tag because they were tagless
    %+  expect-eq
      !>(%0)
    !>(-.imported-prv)
  ::
    %+  expect-eq
      !>(%0)
    !>(-.imported-pub)
  ==
::
++  test-import-master-pubkey-version-migration
  ::  test that old coil-v0 master pubkeys get migrated to coil-v3 format
  ::  when importing via import-master-pubkey command
  ::
  ::  first create a wallet with some keys
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get the master public key from the wallet
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  ~&  >  ['debug: original master pub' master-pub]
  ~&  >  ['debug: original master pub version' -.master-pub]
  ::
  ::  manually construct old-format coil (coil-v0)
  ::  old format: coil-data [=key =cc]
  ::  new format: [%0|%1 coil-data]
  =/  old-format-coil=coil-v0:wt
    [%coil [%pub p.key.master-pub] cc.master-pub]
  ~&  >  ['debug: old format coil' old-format-coil]
  ::
  ::  create fresh wallet and import the old-format master pubkey
  ::  TODO doesn't actually create a fresh wallet - figure out how
  ::  to do that using helpers
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-master-pubkey old-format-coil] wal)
  ::
  ::  get the imported master pubkey
  =/  imported-master-pub=coil  ~(master get:(vault wal2) %pub)
  ~&  >  ['debug: imported master pub' imported-master-pub]
  ~&  >  ['debug: imported master pub version' -.imported-master-pub]
  ::
  ::  verify the imported key matches the original key data
  ;:  weld
    ::  verify public key matches
    %+  expect-eq
      !>(p.key.master-pub)
    !>(p.key.imported-master-pub)
  ::
    ::  verify chain code matches
    %+  expect-eq
      !>(cc.master-pub)
    !>(cc.imported-master-pub)
  ::
    ::  verify the imported key is in new format (coil-v3)
    ::  it should have %0 as the head (converted from old format)
    %+  expect-eq
      !>(%0)
    !>(-.imported-master-pub)
  ::
    ::  verify the key type is preserved
    %+  expect-eq
      !>(%pub)
    !>(-.key.imported-master-pub)
  ==
::
++  test-import-master-pubkey-new-format-preserved
  ::  test that new coil-v3 master pubkeys are preserved unchanged
  ::  when importing via import-master-pubkey command
  ::
  ::  first create a wallet with some keys
  =/  [effs=(list effect) wal=_wal]
    (pok 0 [%keygen entropy salt] wal)
  ::
  ::  get the master public key from the wallet (already in new format)
  =/  master-pub=coil  ~(master get:(vault wal) %pub)
  ~&  >  ['debug: original master pub' master-pub]
  ~&  >  ['debug: original master pub version' -.master-pub]
  ::
  ::  create fresh wallet and import the new-format master pubkey
  =/  [effs=(list effect) wal2=_wal]
    (pok 0 [%import-master-pubkey master-pub] wal)
  ::
  ::  get the imported master pubkey
  =/  imported-master-pub=coil  ~(master get:(vault wal2) %pub)
  ~&  >  ['debug: imported master pub' imported-master-pub]
  ~&  >  ['debug: imported master pub version' -.imported-master-pub]
  ::
  ::  verify the imported key matches the original key exactly
  ;:  weld
    ::  verify public key matches
    %+  expect-eq
      !>(p.key.master-pub)
    !>(p.key.imported-master-pub)
  ::
    ::  verify chain code matches
    %+  expect-eq
      !>(cc.master-pub)
    !>(cc.imported-master-pub)
  ::
    ::  verify the imported key version is preserved
    %+  expect-eq
      !>(-.master-pub)
    !>(-.imported-master-pub)
  ::
    ::  verify the key type is preserved
    %+  expect-eq
      !>(-.key.master-pub)
    !>(-.key.imported-master-pub)
  ==
--  ::  keygen-tests
