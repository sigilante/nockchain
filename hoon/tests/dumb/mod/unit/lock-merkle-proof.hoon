/=  tx-engine  /common/tx-engine
/=  helpers  /tests/dumb/helpers
/=  *  /common/zeke
/=  *  /common/test
|_  constants=blockchain-constants:tx-engine
+*  t  ~(. tx-engine constants)
    h  ~(. helpers constants)
::
++  test-lock-merkle-proof-valid-2
  =/  pkh-left  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-right  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  sc-left=spend-condition:t  form.pkh-left
  =/  sc-right=spend-condition:t  form.pkh-right
  =/  lock=lock:t  [%2 [sc-left sc-right]]
  =/  proof-left=lock-merkle-proof:t
    (build-lock-merkle-proof:lock:t lock 1)
  =/  proof-right=lock-merkle-proof:t
    (build-lock-merkle-proof:lock:t lock 2)
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  left-ok=?  (check:lock-merkle-proof:t proof-left parent-firstname)
  =/  right-ok=?  (check:lock-merkle-proof:t proof-right parent-firstname)
  %+  expect-eq
    !>  [%.y %.y]
  !>  [left-ok right-ok]
::
++  test-lock-merkle-proof-fake
  =/  pkh-left  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-right  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  sc-left=spend-condition:t  form.pkh-left
  =/  sc-right=spend-condition:t  form.pkh-right
  =/  lock=lock:t  [%2 [sc-left sc-right]]
  =/  proof-left=lock-merkle-proof-full:v1:t
    (build-lock-merkle-proof-full:lock:t lock 1)
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  valid=?  (check:lock-merkle-proof:t proof-left parent-firstname)
  =/  wrong-leaf=lock-merkle-proof-full:v1:t
    proof-left(spend-condition sc-right)
  =/  wrong-leaf-res=?
    (check:lock-merkle-proof:t wrong-leaf parent-firstname)
  ::  twiddle the first element of lock-root hash to produce fake root
  =/  fake-root=hash:t  lock-root(- (mix +2:lock-root +6:lock-root))
  =/  forged-proof=lock-merkle-proof-full:v1:t
    proof-left(merk-proof merk-proof.proof-left(root fake-root))
  =/  forged-res=?
    (check:lock-merkle-proof:t forged-proof parent-firstname)
  %+  expect-eq
    !>  [%.y %.n %.n]
  !>  [valid wrong-leaf-res forged-res]
::
++  test-lock-merkle-proof-arity-four
  =/  pkh-one  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-two  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  pkh-three  (make-pkh-from-sig:spend-condition:t p:default-keys-3:h)
  =/  hax-four  (make-hax:spend-condition:t 42)
  =/  sc-one=spend-condition:t  form.pkh-one
  =/  sc-two=spend-condition:t  form.pkh-two
  =/  sc-three=spend-condition:t  form.pkh-three
  =/  sc-four=spend-condition:t  form.hax-four
  =/  lock=lock:t  (from-list:lock:t ~[sc-one sc-two sc-three sc-four])
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  res-one=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 1) parent-firstname)
  =/  res-two=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 2) parent-firstname)
  =/  res-three=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 3) parent-firstname)
  =/  res-four=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 4) parent-firstname)
  %+  expect-eq
    !>  [%.y %.y %.y %.y]
  !>  [res-one res-two res-three res-four]
::
++  test-lock-merkle-proof-arity-eight
  =/  pkh-one  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-two  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  pkh-three  (make-pkh-from-sig:spend-condition:t p:default-keys-3:h)
  =/  hax-four  (make-hax:spend-condition:t 100)
  =/  hax-five  (make-hax:spend-condition:t 101)
  =/  hax-six  (make-hax:spend-condition:t 102)
  =/  hax-seven  (make-hax:spend-condition:t 103)
  =/  hax-eight  (make-hax:spend-condition:t 104)
  =/  sc-one=spend-condition:t  form.pkh-one
  =/  sc-two=spend-condition:t  form.pkh-two
  =/  sc-three=spend-condition:t  form.pkh-three
  =/  sc-four=spend-condition:t  form.hax-four
  =/  sc-five=spend-condition:t  form.hax-five
  =/  sc-six=spend-condition:t  form.hax-six
  =/  sc-seven=spend-condition:t  form.hax-seven
  =/  sc-eight=spend-condition:t  form.hax-eight
  =/  lock=lock:t
    %-  from-list:lock:t
    ~[sc-one sc-two sc-three sc-four sc-five sc-six sc-seven sc-eight]
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  res-one=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 1) parent-firstname)
  =/  res-two=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 2) parent-firstname)
  =/  res-three=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 3) parent-firstname)
  =/  res-four=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 4) parent-firstname)
  =/  res-five=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 5) parent-firstname)
  =/  res-six=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 6) parent-firstname)
  =/  res-seven=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 7) parent-firstname)
  =/  res-eight=?
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock 8) parent-firstname)
  %+  expect-eq
    !>  [%.y %.y %.y %.y %.y %.y %.y %.y]
  !>  [res-one res-two res-three res-four res-five res-six res-seven res-eight]
::
++  test-lock-merkle-proof-arity-sixteen
  =/  pkh-one  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-two  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  pkh-three  (make-pkh-from-sig:spend-condition:t p:default-keys-3:h)
  =/  hax-four  (make-hax:spend-condition:t 200)
  =/  hax-five  (make-hax:spend-condition:t 201)
  =/  hax-six  (make-hax:spend-condition:t 202)
  =/  hax-seven  (make-hax:spend-condition:t 203)
  =/  hax-eight  (make-hax:spend-condition:t 204)
  =/  hax-nine  (make-hax:spend-condition:t 205)
  =/  hax-ten  (make-hax:spend-condition:t 206)
  =/  hax-eleven  (make-hax:spend-condition:t 207)
  =/  hax-twelve  (make-hax:spend-condition:t 208)
  =/  hax-thirteen  (make-hax:spend-condition:t 209)
  =/  hax-fourteen  (make-hax:spend-condition:t 210)
  =/  hax-fifteen  (make-hax:spend-condition:t 211)
  =/  hax-sixteen  (make-hax:spend-condition:t 212)
  =/  scs=(list spend-condition:t)
    :~  form.pkh-one
        form.pkh-two
        form.pkh-three
        form.hax-four
        form.hax-five
        form.hax-six
        form.hax-seven
        form.hax-eight
        form.hax-nine
        form.hax-ten
        form.hax-eleven
        form.hax-twelve
        form.hax-thirteen
        form.hax-fourteen
        form.hax-fifteen
        form.hax-sixteen
    ==
  =/  lock=lock:t  (from-list:lock:t scs)
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  indices=(list @)  (gulf 1 16)
  =/  results=(list ?)
    %+  turn  indices
    |=  idx=@
    (check:lock-merkle-proof:t (build-lock-merkle-proof:lock:t lock idx) parent-firstname)
  %+  expect-eq
    !>  (reap 16 %.y)
  !>  results
::
++  test-lock-merkle-proof-six
  =/  pkh-one  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-two  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  pkh-three  (make-pkh-from-sig:spend-condition:t p:default-keys-3:h)
  =/  hax-four  (make-hax:spend-condition:t 300)
  =/  hax-five  (make-hax:spend-condition:t 301)
  =/  hax-six  (make-hax:spend-condition:t 302)
  =/  filler=spend-condition:t  ~[[%brn ~]]
  =/  scs=(list spend-condition:t)
    :~  form.pkh-one
        form.pkh-two
        form.pkh-three
        form.hax-four
        form.hax-five
        form.hax-six
    ==
  =/  lock=lock:t  (from-list:lock:t scs)
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  =/  proof-indices=(list @)  (gulf 1 8)
  =/  proofs=(list lock-merkle-proof:t)
    %+  turn  proof-indices
    |=  idx=@
    (build-lock-merkle-proof:lock:t lock idx)
  =/  results=(list ?)
    %+  turn  proofs
    |=  lmp=lock-merkle-proof:t
    (check:lock-merkle-proof:t lmp parent-firstname)
  =/  padded=(list ?)
    %+  turn  (slag 6 proofs)
    |=  lmp=lock-merkle-proof:t
    =/  sc=spend-condition:t
      ?:  ?=([%full * * *] lmp)
        =+  [ver sc ax mp]=lmp
        sc
      =+  [sc ax mp]=lmp
      sc
    =(sc filler)
  ;:  weld
    %+  expect-eq
      !>  (reap 8 %.y)
     !>  results
    %+  expect-eq
      !>  (reap 2 %.y)
     !>  padded
  ==
::
::  Version-specific tests for stub/full lock-merkle-proof
::
++  test-lock-merkle-proof-stub-axis-must-be-one
  ::  stub proofs must have axis=1, reject axis>1
  ::  For a 2-branch lock, even leaf-number=1 has axis>1 in the merkle tree
  =/  pkh-left  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-right  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  sc-left=spend-condition:t  form.pkh-left
  =/  sc-right=spend-condition:t  form.pkh-right
  =/  lock-multi=lock:t  [%2 [sc-left sc-right]]
  =/  lock-root-multi=hash:t  (hash:lock:t lock-multi)
  =/  parent-firstname-multi=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root-multi])
  ::  build a stub proof for a multi-branch lock - axis will be >1
  =/  proof-stub-multi=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock-multi 1)
  ::  stub check should reject because axis>1 for multi-branch locks
  =/  stub-multi-rejected=?
    !(check:lock-merkle-proof-stub:v1:t proof-stub-multi parent-firstname-multi)
  ::  For a single spend-condition lock, axis IS 1
  =/  lock-single=lock:t  sc-left
  =/  lock-root-single=hash:t  (hash:lock:t lock-single)
  =/  parent-firstname-single=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root-single])
  =/  proof-stub-single=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock-single 1)
  ::  stub check should accept axis=1 for single spend-condition locks
  =/  stub-single-accepted=?
    (check:lock-merkle-proof-stub:v1:t proof-stub-single parent-firstname-single)
  %+  expect-eq
    !>  [%.y %.y]
  !>  [stub-multi-rejected stub-single-accepted]
::
++  test-lock-merkle-proof-stub-full-hash-divergence
  ::  stub and full must produce DIFFERENT hashes for the same underlying data
  ::  This is critical: if they were the same, old proofs could be replayed
  =/  pkh  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  sc=spend-condition:t  form.pkh
  =/  lock=lock:t  sc  ::  single spend-condition lock
  ::  build both versions
  =/  proof-stub=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock 1)
  =/  proof-full=lock-merkle-proof-full:v1:t
    (build-lock-merkle-proof-full:lock:t lock 1)
  ::  hash both
  =/  hash-stub=hash:t  (hash:lock-merkle-proof-stub:v1:t proof-stub)
  =/  hash-full=hash:t  (hash:lock-merkle-proof-full:v1:t proof-full)
  ::  they MUST be different
  =/  hashes-differ=?  !=(hash-stub hash-full)
  ::  sanity: same version hashes itself consistently
  =/  stub-deterministic=?  =(hash-stub (hash:lock-merkle-proof-stub:v1:t proof-stub))
  =/  full-deterministic=?  =(hash-full (hash:lock-merkle-proof-full:v1:t proof-full))
  %+  expect-eq
    !>  [%.y %.y %.y]
  !>  [hashes-differ stub-deterministic full-deterministic]
::
++  test-lock-merkle-proof-stub-backward-compat
  ::  raw stub data (3-tuple without %1 tag) must validate via wrapper
  =/  pkh  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  sc=spend-condition:t  form.pkh
  =/  lock=lock:t  sc
  =/  lock-root=hash:t  (hash:lock:t lock)
  =/  parent-firstname=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root])
  ::  build raw stub proof (3-tuple)
  =/  proof-stub=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock 1)
  ::  cast to wrapper type and validate
  =/  proof-wrapper=lock-merkle-proof:t  proof-stub
  =/  wrapper-accepts-stub=?
    (check:lock-merkle-proof:t proof-wrapper parent-firstname)
  %+  expect-eq
    !>  %.y
  !>  wrapper-accepts-stub
::
++  test-lock-merkle-proof-wrapper-version-dispatch
  ::  verify wrapper correctly dispatches to stub vs full check logic
  =/  pkh-left  (make-pkh-from-sig:spend-condition:t p:default-keys-1:h)
  =/  pkh-right  (make-pkh-from-sig:spend-condition:t p:default-keys-2:h)
  =/  sc-left=spend-condition:t  form.pkh-left
  =/  sc-right=spend-condition:t  form.pkh-right
  ::  For stub tests, use single spend-condition lock (axis=1)
  =/  lock-single=lock:t  sc-left
  =/  lock-root-single=hash:t  (hash:lock:t lock-single)
  =/  parent-firstname-single=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root-single])
  ::  stub proof at axis=1 (single lock) should pass wrapper
  =/  proof-stub=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock-single 1)
  =/  stub-via-wrapper=?
    (check:lock-merkle-proof:t proof-stub parent-firstname-single)
  ::  For full tests, use multi-branch lock to show axis>1 works
  =/  lock-multi=lock:t  [%2 [sc-left sc-right]]
  =/  lock-root-multi=hash:t  (hash:lock:t lock-multi)
  =/  parent-firstname-multi=hash:t
    (hash-hashable:tip5 [leaf+& hash+lock-root-multi])
  ::  full proof at axis>1 should pass wrapper (full allows any axis)
  =/  proof-full=lock-merkle-proof-full:v1:t
    (build-lock-merkle-proof-full:lock:t lock-multi 2)
  =/  full-via-wrapper=?
    (check:lock-merkle-proof:t proof-full parent-firstname-multi)
  ::  stub proof from multi-branch lock should FAIL via wrapper (axis>1)
  =/  proof-stub-multi=lock-merkle-proof-stub:v1:t
    (build-lock-merkle-proof-stub:lock:t lock-multi 1)
  =/  stub-multi-via-wrapper=?
    (check:lock-merkle-proof:t proof-stub-multi parent-firstname-multi)
  %+  expect-eq
    !>  [%.y %.y %.n]
  !>  [stub-via-wrapper full-via-wrapper stub-multi-via-wrapper]
--
