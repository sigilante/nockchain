::  z-map/z-mip robustness tests using nockchain types
::
::  tests the integrity and performance of z-map/z-mip data structures
::  with realistic nockchain types but without transaction logic
::
/=  *  /common/zoon
/=  *  /common/zeke
/=  *  /common/test
/=  t  /common/tx-engine
/=  dk  /apps/dumbnet/lib/types
/*  blocks-jam  %jam  /jams/small-blocks/jam
::
|%
::  helper to create unique block-ids
++  make-block-id
  |=  n=@
  ^-  block-id:t
  (atom-to-digest:tip5 n)
::
::  helper to create unique nnames
++  make-nname
  |=  n=@
  ^-  nname:t
  =/  hash1=hash:t  (atom-to-digest:tip5 n)
  =/  hash2=hash:t  (atom-to-digest:tip5 (mul n 7))
  [hash1 hash2 ~]
::
::  helper to create simple nnotes with minimal fields
++  make-nnote
  |=  [n=@ page=page-number:t]
  ^-  nnote:t
  =/  nam=nname:t  (make-nname n)
  =/  assets=coins:t  (mul n 100)
  ::  create a simple lock with a deterministic pubkey
  =/  pubkey=a-pt:curve:cheetah
    =/  scalar=@  (mod n (dec g-order:curve:cheetah))
    (ch-scal:affine:curve:cheetah scalar a-gen:curve:cheetah)
  =/  lok=sig:t  (new:sig:t pubkey)
  %*  .  *nnote:v0:t
    name         nam
    sig          lok
    assets       assets
    origin-page  page
    source       [(atom-to-digest:tip5 (mul n 3)) %.n]
    timelock     *timelock:t
  ==
::
::  check apt for balance map (z-mip)
++  check-balance-apt
  |=  balance=(z-mip block-id:t nname:t nnote:t)
  ^-  ?
  ?&  ~(apt z-by balance)  ::  outer map is valid
      %+  levy  ~(tap z-by balance)
      |=  [bid=block-id:t inner=(z-map nname:t nnote:t)]
      ~(apt z-by inner)  ::  each inner map is valid
  ==
::
::  basic z-mip operation tests
++  test-empty-balance-apt
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  %+  expect-eq  !>(%.y)
  !>((check-balance-apt balance))
::
++  test-single-entry-apt
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  =/  bid=block-id:t  (make-block-id 1)
  =/  note=nnote:t  (make-nnote 1 1)
  ?>  ?=(^ -.note)
  =/  nam=nname:t  name.note
  =.  balance  (~(put z-bi balance) bid nam note)
  %+  expect-eq  !>(%.y)
  !>((check-balance-apt balance))
::
::  test adding many entries to single block
++  test-single-block-many-entries
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  =/  bid=block-id:t  (make-block-id 1)
  ::  add 100 unique nnotes to same block
  =|  i=@
  |-
  ?:  =(i 100)
    %+  expect-eq  !>(%.y)
    !>((check-balance-apt balance))
  =/  note=nnote:t  (make-nnote i 1)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test many blocks with single entry each
++  test-many-blocks-single-entry
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  add 100 blocks, each with one nnote
  =|  i=@
  |-
  ?:  =(i 100)
    %+  expect-eq  !>(%.y)
    !>((check-balance-apt balance))
  =/  bid=block-id:t  (make-block-id i)
  =/  note=nnote:t  (make-nnote i i)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test many blocks with many entries
++  test-many-blocks-many-entries
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  add 50 blocks, each with 20 nnotes
  =|  b=@
  |-
  ?:  =(b 50)
    %+  expect-eq  !>(%.y)
    !>((check-balance-apt balance))
  =/  bid=block-id:t  (make-block-id b)
  ::  add 20 notes to this block
  =|  n=@
  |-
  ?:  =(n 20)
    ^$(b +(b))
  =/  note-id=@  (add (mul b 1.000) n)
  =/  note=nnote:t  (make-nnote note-id b)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(n +(n))
::
::  test deletion maintains apt
++  test-deletion-maintains-apt
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  populate with data
  =|  i=@
  |-
  ?:  =(i 100)
    =/  apt1=?  (check-balance-apt balance)
    ::  delete every other entry
    =|  j=@
    |-
    ?:  =(j 100)
      %+  expect-eq  !>([%.y %.y])
      !>([apt1 (check-balance-apt balance)])
    ?:  =(0 (mod j 2))
      =/  bid=block-id:t  (make-block-id j)
      =/  note=nnote:t  (make-nnote j j)
      ?>  ?=(^ -.note)
      =.  balance  (~(del z-bi balance) bid name.note)
      $(j +(j))
    $(j +(j))
  =/  bid=block-id:t  (make-block-id i)
  =/  note=nnote:t  (make-nnote i i)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test z-bi operations on large dataset
++  test-z-bi-operations-scale
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  populate with 200 entries across 10 blocks
  =|  b=@
  |-
  ?:  =(b 10)
    =/  apt1=?  (check-balance-apt balance)
    ::  test various z-bi operations
    =/  test-bid=block-id:t  (make-block-id 5)
    =/  test-note=nnote:t  (make-nnote 500 5)
    ?>  ?=(^ -.test-note)
    =/  test-name=nname:t  name.test-note
    ::  test get
    =/  got=(unit nnote:t)  (~(get z-bi balance) test-bid test-name)
    =/  has-entry=?  (~(has z-bi balance) test-bid test-name)
    ::  test key operation
    =/  keys=(z-set nname:t)  (~(key z-bi balance) test-bid)
    =/  key-count=@  ~(wyt z-in keys)
    %+  expect-eq  !>([%.y %.y %.y 20])
    !>([apt1 ?=(^ got) has-entry key-count])
  =/  bid=block-id:t  (make-block-id b)
  =|  n=@
  |-
  ?:  =(n 20)
    ^$(b +(b))
  =/  note-id=@  (add (mul b 100) n)
  =/  note=nnote:t  (make-nnote note-id b)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(n +(n))
::
::  test extreme key patterns
++  test-extreme-key-patterns
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  test with very large and very small key values
  =/  keys=(list @)  ~[0 1 (dec (bex 64)) (bex 63) (bex 32) (bex 16) 1.337 42.069]
  =/  apt1=?  (check-balance-apt balance)
  =.  balance
    %+  roll  keys
    |=  [k=@ bal=_balance]
    =/  bid=block-id:t  (make-block-id k)
    =/  note=nnote:t  (make-nnote k 1)
    ?>  ?=(^ -.note)
    (~(put z-bi bal) bid name.note note)
  =/  apt2=?  (check-balance-apt balance)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
::  test z-mip with maximum realistic load
++  test-maximum-load
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  simulate 1000 entries across 100 blocks
  =/  blocks  100
  =/  entries-per-block  10
  =|  b=@
  |-
  ?:  =(b blocks)
    =/  apt=?  (check-balance-apt balance)
    =/  total-blocks=@  ~(wyt z-by balance)
    %+  expect-eq  !>([%.y blocks])
    !>([apt total-blocks])
  =/  bid=block-id:t  (make-block-id b)
  =|  e=@
  |-
  ?:  =(e entries-per-block)
    ^$(b +(b))
  =/  entry-id=@  (add (mul b 10.000) e)
  =/  note=nnote:t  (make-nnote entry-id b)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(e +(e))
::
::  test collision patterns
++  test-hash-collision-patterns
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  create entries with similar hash patterns
  ::  using sequential numbers that might hash similarly
  =|  i=@
  |-
  ?:  =(i 200)
    %+  expect-eq  !>(%.y)
    !>((check-balance-apt balance))
  =/  bid=block-id:t  (make-block-id (mod i 20))  :: reuse block ids
  =/  note=nnote:t  (make-nnote i (mod i 20))
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test empty block cleanup
++  test-empty-block-cleanup
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  add entries to multiple blocks
  =|  i=@
  |-
  ?:  =(i 50)
    =/  apt1=?  (check-balance-apt balance)
    =/  initial-blocks=@  ~(wyt z-by balance)
    ::  remove all entries from first 25 blocks
    =|  j=@
    |-
    ?:  =(j 25)
      =/  apt2=?  (check-balance-apt balance)
      =/  final-blocks=@  ~(wyt z-by balance)
      %+  expect-eq  !>([%.y %.y 50 25])
      !>([apt1 apt2 initial-blocks final-blocks])
    =/  bid=block-id:t  (make-block-id j)
    =/  note=nnote:t  (make-nnote j j)
    ?>  ?=(^ -.note)
    =.  balance  (~(del z-bi balance) bid name.note)
    $(j +(j))
  =/  bid=block-id:t  (make-block-id i)
  =/  note=nnote:t  (make-nnote i i)
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test tap operation on large z-mip
++  test-tap-operation-scale
  =/  balance=(z-mip block-id:t nname:t nnote:t)
    *(z-mip block-id:t nname:t nnote:t)
  ::  populate with entries
  =|  i=@
  |-
  ?:  =(i 100)
    =/  apt=?  (check-balance-apt balance)
    =/  all-entries=(list [block-id:t nname:t nnote:t])
      ~(tap z-bi balance)
    =/  entry-count=@  (lent all-entries)
    %+  expect-eq  !>([%.y 100])
    !>([apt entry-count])
  =/  bid=block-id:t  (make-block-id (mod i 10))
  =/  note=nnote:t  (make-nnote i (mod i 10))
  ?>  ?=(^ -.note)
  =.  balance  (~(put z-bi balance) bid name.note note)
  $(i +(i))
::
::  test serialized block map is valid
::
::  small-blocks.jam is a serialized z-map of block-id:t to page:t
::  from a live node, with the pow field removed
++  test-block-map
  =/  block-map=(z-map block-id:t page:t)
    %-  need
    %-  (soft (z-map block-id:t page:t))
    (cue q.blocks-jam)
  =/  block-count=@  ~(wyt z-by block-map)
  %+  expect-eq  !>([%.y 11.412])
  !>([~(apt z-by block-map) block-count])
--
