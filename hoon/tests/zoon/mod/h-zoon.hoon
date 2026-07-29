::  tests/zoon/mod/h-zoon.hoon
::
::    pins deterministic hashed-key container behavior.
::
::    the lower half of this file (after ++rand-token) is a randomized
::    differential suite. each h-* container engine runs the same op
::    sequence against its z-* twin; on every step we assert
::      ?&  ~(apt h-by ...)
::          =((hz-* h-noun) z-noun)
::          probe-equalities for every key inserted so far
::      ==
::    new h-* operations land here as additional draws in +draw-map-op /
::    +draw-set-op so the randomizer exercises them automatically.
::
/=  *  /common/h-zoon
/=  *  /common/test
::
|%
++  d
  |=  n=@
  ^-  noun-digest:tip5:z
  (atom-to-digest:tip5:z `@ux`n)
::
++  md
  |=  [a=@ b=@]
  ^-  noun-digests:z
  ~[(d a) (d b)]
::
++  apt-hashed-set
  |=  set=(hset-tree hashed)
  ^-  ?
  ~(apt h-in set)
::
++  apt-hashed-map
  |=  map=(hmap-tree (pair hashed @))
  ^-  ?
  ~(apt h-by map)
::
++  old-z-map
  |$  [key value]
  $|  (tree (pair key value))
  |=(a=(tree (pair)) ?:(=(~ a) & ~(apt z-by a)))
::
++  old-z-set
  |$  [item]
  $|  (tree item)
  |=(a=(tree) ?:(=(~ a) & ~(apt z-in a)))
::
++  test-h-map-duplicate-puts-replace-without-growing
  =/  m=(h-map noun-digest:tip5:z @)
    %-  ~(gas h-by *(h-map noun-digest:tip5:z @))
    ~[[(d 1) 10] [(d 2) 20] [(d 1) 11] [(d 3) 30] [(d 2) 22]]
  =/  z=(z-map noun-digest:tip5:z @)  (hz-molt m)
  %+  expect-eq
    !>([%.y 3 3 11 22 30 %.y %.y])
  !>  :*  ~(apt h-by m)
          ~(wyt h-by m)
          ~(wyt z-by z)
          (~(got h-by m) (d 1))
          (~(got h-by m) (d 2))
          (~(got z-by z) (d 3))
          (~(has h-by m) (d 1))
          (~(has h-by m) (d 2))
      ==
::
++  test-h-set-duplicate-puts-delete-empty-boundary
  =/  s=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 1) (d 3) (d 2)])
  =/  s1=(h-set noun-digest:tip5:z)  (~(del h-in s) (d 2))
  =/  s2=(h-set noun-digest:tip5:z)  (~(del h-in s1) (d 1))
  =/  s3=(h-set noun-digest:tip5:z)  (~(del h-in s2) (d 3))
  %+  expect-eq
    !>([%.y 3 %.n %.y %.y 2 1 0])
  !>  :*  ~(apt h-in s)
          ~(wyt h-in s)
          (~(has h-in s1) (d 2))
          (~(has h-in s1) (d 1))
          ~(apt h-in s2)
          ~(wyt h-in s1)
          ~(wyt h-in s2)
          ~(wyt h-in s3)
      ==
::
++  test-h-map-identical-intersection-terminates-and-preserves-values
  =/  a=(h-map noun-digest:tip5:z @)
    %-  ~(gas h-by *(h-map noun-digest:tip5:z @))
    ~[[(d 1) 1] [(d 2) 2] [(d 3) 3] [(d 4) 4] [(d 5) 5]]
  =/  int=(h-map noun-digest:tip5:z @)  (~(int h-by a) a)
  %+  expect-eq
    !>([%.y %.y 5 %.y %.y 4 5])
  !>  :*  ~(apt h-by a)
          ~(apt h-by int)
          ~(wyt h-by int)
          =((hz-molt int) (hz-molt a))
          (~(has h-by int) (d 4))
          (~(got h-by int) (d 4))
          (~(got h-by int) (d 5))
      ==
::
++  test-h-map-intersection-equal-key-takes-right-value
  =/  left=(h-map noun-digest:tip5:z @)
    (~(put h-by *(h-map noun-digest:tip5:z @)) (d 7) 70)
  =/  right=(h-map noun-digest:tip5:z @)
    (~(put h-by *(h-map noun-digest:tip5:z @)) (d 7) 700)
  =/  lr=(h-map noun-digest:tip5:z @)  (~(int h-by left) right)
  =/  rl=(h-map noun-digest:tip5:z @)  (~(int h-by right) left)
  %+  expect-eq
    !>([%.y %.y 1 700 70])
  !>  :*  ~(apt h-by lr)
          ~(apt h-by rl)
          ~(wyt h-by lr)
          (~(got h-by lr) (d 7))
          (~(got h-by rl) (d 7))
      ==
::
++  test-h-set-identical-intersection-terminates
  =/  s=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3) (d 4) (d 5)])
  =/  int=(h-set noun-digest:tip5:z)  (~(int h-in s) s)
  %+  expect-eq
    !>([%.y %.y 5 %.y %.y])
  !>  :*  ~(apt h-in s)
          ~(apt h-in int)
          ~(wyt h-in int)
          =((hz-silt int) (hz-silt s))
          (~(has h-in int) (d 4))
      ==
::
++  test-h-map-algebra-matches-z-map-after-conversion
  =/  za=(z-map noun-digest:tip5:z @)
    %-  ~(gas z-by *(z-map noun-digest:tip5:z @))
    ~[[(d 1) 1] [(d 2) 2] [(d 3) 3] [(d 4) 4]]
  =/  zb=(z-map noun-digest:tip5:z @)
    %-  ~(gas z-by *(z-map noun-digest:tip5:z @))
    ~[[(d 3) 30] [(d 4) 40] [(d 5) 5] [(d 6) 6]]
  =/  ha=(h-map noun-digest:tip5:z @)  (zh-molt za)
  =/  hb=(h-map noun-digest:tip5:z @)  (zh-molt zb)
  =/  z-uni=(z-map noun-digest:tip5:z @)  (~(uni z-by za) zb)
  =/  z-int=(z-map noun-digest:tip5:z @)  (~(int z-by za) zb)
  =/  z-dif=(z-map noun-digest:tip5:z @)  (~(dif z-by za) zb)
  =/  h-uni=(h-map noun-digest:tip5:z @)  (~(uni h-by ha) hb)
  =/  h-int=(h-map noun-digest:tip5:z @)  (~(int h-by ha) hb)
  =/  h-dif=(h-map noun-digest:tip5:z @)  (~(dif h-by ha) hb)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y])
  !>  :*  =((hz-molt h-uni) z-uni)
          =((hz-molt h-int) z-int)
          =((hz-molt h-dif) z-dif)
          ~(apt h-by h-uni)
          ~(apt h-by h-int)
          ~(apt h-by h-dif)
      ==
::
++  test-h-set-algebra-matches-z-set-after-conversion
  =/  za=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3) (d 4)])
  =/  zb=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 3) (d 4) (d 5) (d 6)])
  =/  ha=(h-set noun-digest:tip5:z)  (zh-silt za)
  =/  hb=(h-set noun-digest:tip5:z)  (zh-silt zb)
  =/  h-uni=(h-set noun-digest:tip5:z)  (~(uni h-in ha) hb)
  =/  h-int=(h-set noun-digest:tip5:z)  (~(int h-in ha) hb)
  =/  h-dif=(h-set noun-digest:tip5:z)  (~(dif h-in ha) hb)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y])
  !>  :*  =((hz-silt h-uni) (~(uni z-in za) zb))
          =((hz-silt h-int) (~(int z-in za) zb))
          =((hz-silt h-dif) (~(dif z-in za) zb))
          ~(apt h-in h-uni)
          ~(apt h-in h-int)
          ~(apt h-in h-dif)
      ==
::
++  test-h-jug-delete-removes-empty-inner-set
  =/  j=(h-jug noun-digest:tip5:z noun-digest:tip5:z)
    %-  ~(gas h-ju *(h-jug noun-digest:tip5:z noun-digest:tip5:z))
    ~[[p=(d 1) q=(d 10)] [p=(d 1) q=(d 11)] [p=(d 2) q=(d 20)]]
  =/  j1=(h-jug noun-digest:tip5:z noun-digest:tip5:z)  (~(del h-ju j) (d 1) (d 10))
  =/  j2=(h-jug noun-digest:tip5:z noun-digest:tip5:z)  (~(del h-ju j1) (d 1) (d 11))
  =/  j3=(h-jug noun-digest:tip5:z noun-digest:tip5:z)  (~(del h-ju j2) (d 2) (d 20))
  =/  s1=(h-set noun-digest:tip5:z)  (~(get h-ju j1) (d 1))
  %+  expect-eq
    !>([%.y %.y %.y %.n %.n 1 0])
  !>  :*  ~(apt h-by j)
          ~(apt h-by j1)
          (~(has h-ju j1) (d 1) (d 11))
          (~(has h-by j2) (d 1))
          (~(has h-by j3) (d 2))
          ~(wyt h-in s1)
          ~(wyt h-by j3)
      ==
::
++  test-h-mip-delete-removes-empty-inner-map
  =/  m=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)
    *(h-mip noun-digest:tip5:z noun-digest:tip5:z @)
  =.  m  (~(put h-bi m) (d 1) (d 10) 110)
  =.  m  (~(put h-bi m) (d 1) (d 11) 111)
  =.  m  (~(put h-bi m) (d 2) (d 20) 220)
  =/  m1=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)  (~(del h-bi m) (d 1) (d 10))
  =/  m2=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)  (~(del h-bi m1) (d 1) (d 11))
  =/  m3=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)  (~(del h-bi m2) (d 2) (d 20))
  %+  expect-eq
    !>([%.y %.y %.n %.n 111 0])
  !>  :*  ~(apt h-by m)
          (~(has h-bi m1) (d 1) (d 11))
          (~(has h-by m2) (d 1))
          (~(has h-by m3) (d 2))
          (~(got h-bi m1) (d 1) (d 11))
          ~(wyt h-by m3)
      ==
::
++  test-h-digest-list-keys-roundtrip
  =/  za=(z-set noun-digests:z)
    (~(gas z-in *(z-set noun-digests:z)) ~[(md 1 9) (md 1 8) (md 2 0) (md 1 9)])
  =/  ha=(h-set noun-digests:z)  (zh-silt za)
  =/  z-back=(z-set noun-digests:z)  (hz-silt ha)
  %+  expect-eq
    !>([%.y 3 %.y %.y %.y])
  !>  :*  ~(apt h-in ha)
          ~(wyt h-in ha)
          =((hz-silt ha) za)
          =((zh-silt z-back) ha)
          (~(has h-in ha) (md 1 8))
      ==
::
++  test-z-and-h-container-tags-reject-direct-mixing
  =/  zset=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  hset=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  empty-zset=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  =/  empty-hset=(h-set noun-digest:tip5:z)  *(h-set noun-digest:tip5:z)
  =/  zmap=(z-map noun-digest:tip5:z @)
    (~(put z-by *(z-map noun-digest:tip5:z @)) (d 3) 30)
  =/  hmap=(h-map noun-digest:tip5:z @)
    (~(put h-by *(h-map noun-digest:tip5:z @)) (d 3) 30)
  =/  empty-zmap=(z-map noun-digest:tip5:z @)  *(z-map noun-digest:tip5:z @)
  =/  empty-hmap=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  =/  zset-as-hset=(unit (h-set noun-digest:tip5:z))
    ((soft (h-set noun-digest:tip5:z)) zset)
  =/  hset-as-zset=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) hset)
  =/  empty-zset-as-hset=(unit (h-set noun-digest:tip5:z))
    ((soft (h-set noun-digest:tip5:z)) empty-zset)
  =/  empty-hset-as-zset=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) empty-hset)
  =/  zmap-as-hmap=(unit (h-map noun-digest:tip5:z @))
    ((soft (h-map noun-digest:tip5:z @)) zmap)
  =/  hmap-as-zmap=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) hmap)
  =/  empty-zmap-as-hmap=(unit (h-map noun-digest:tip5:z @))
    ((soft (h-map noun-digest:tip5:z @)) empty-zmap)
  =/  empty-hmap-as-zmap=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) empty-hmap)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  ?=(~ zset-as-hset)
          ?=(~ hset-as-zset)
          ?=(~ empty-zset-as-hset)
          ?=(~ empty-hset-as-zset)
          ?=(~ zmap-as-hmap)
          ?=(~ hmap-as-zmap)
          ?=(~ empty-zmap-as-hmap)
          ?=(~ empty-hmap-as-zmap)
          =((hz-silt hset) zset)
          =((zh-silt zset) hset)
          =((hz-molt hmap) zmap)
          =((zh-molt zmap) hmap)
      ==
::
++  test-old-z-map-and-z-set-are-noun-equivalent
  =/  new-empty-set=(z-set noun-digest:tip5:z)
    *(z-set noun-digest:tip5:z)
  =/  old-empty-set=(old-z-set noun-digest:tip5:z)
    *(old-z-set noun-digest:tip5:z)
  =/  new-empty-map=(z-map noun-digest:tip5:z @)
    *(z-map noun-digest:tip5:z @)
  =/  old-empty-map=(old-z-map noun-digest:tip5:z @)
    *(old-z-map noun-digest:tip5:z @)
  =/  new-set=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 3) (d 2) (d 5) (d 4)])
  =/  raw-new-set=*  new-set
  =/  old-set-soft=(unit (old-z-set noun-digest:tip5:z))
    ((soft (old-z-set noun-digest:tip5:z)) raw-new-set)
  ?>  ?=(^ old-set-soft)
  =/  old-set=(old-z-set noun-digest:tip5:z)  u.old-set-soft
  =/  raw-old-set=*  old-set
  =/  new-set-soft=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) raw-old-set)
  ?>  ?=(^ new-set-soft)
  =/  new-set-from-old=(z-set noun-digest:tip5:z)  u.new-set-soft
  =/  new-map=(z-map noun-digest:tip5:z @)
    %-  ~(gas z-by *(z-map noun-digest:tip5:z @))
    ~[[(d 1) 10] [(d 3) 30] [(d 2) 20] [(d 5) 50] [(d 4) 40]]
  =/  raw-new-map=*  new-map
  =/  old-map-soft=(unit (old-z-map noun-digest:tip5:z @))
    ((soft (old-z-map noun-digest:tip5:z @)) raw-new-map)
  ?>  ?=(^ old-map-soft)
  =/  old-map=(old-z-map noun-digest:tip5:z @)  u.old-map-soft
  =/  raw-old-map=*  old-map
  =/  new-map-soft=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) raw-old-map)
  ?>  ?=(^ new-map-soft)
  =/  new-map-from-old=(z-map noun-digest:tip5:z @)  u.new-map-soft
  =/  shrunk-new-set=(z-set noun-digest:tip5:z)
    (~(del z-in (~(del z-in new-set) (d 3))) (d 5))
  =/  raw-shrunk-new-set=*  shrunk-new-set
  =/  shrunk-old-set-soft=(unit (old-z-set noun-digest:tip5:z))
    ((soft (old-z-set noun-digest:tip5:z)) raw-shrunk-new-set)
  ?>  ?=(^ shrunk-old-set-soft)
  =/  shrunk-old-set=(old-z-set noun-digest:tip5:z)  u.shrunk-old-set-soft
  =/  raw-shrunk-old-set=*  shrunk-old-set
  =/  shrunk-new-map=(z-map noun-digest:tip5:z @)
    (~(del z-by (~(del z-by new-map) (d 3))) (d 5))
  =/  raw-shrunk-new-map=*  shrunk-new-map
  =/  shrunk-old-map-soft=(unit (old-z-map noun-digest:tip5:z @))
    ((soft (old-z-map noun-digest:tip5:z @)) raw-shrunk-new-map)
  ?>  ?=(^ shrunk-old-map-soft)
  =/  shrunk-old-map=(old-z-map noun-digest:tip5:z @)  u.shrunk-old-map-soft
  =/  raw-shrunk-old-map=*  shrunk-old-map
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  =(`*`old-empty-set `*`new-empty-set)
          =(`*`old-empty-map `*`new-empty-map)
          =(raw-old-set raw-new-set)
          =(new-set-from-old new-set)
          ?=(^ old-set-soft)
          ?=(^ new-set-soft)
          ~(apt z-in new-set-from-old)
          =(raw-old-map raw-new-map)
          =(new-map-from-old new-map)
          ?=(^ old-map-soft)
          ?=(^ new-map-soft)
          ~(apt z-by new-map-from-old)
          =(raw-shrunk-old-set raw-shrunk-new-set)
          =(raw-shrunk-old-map raw-shrunk-new-map)
          =(~(tap z-in new-set-from-old) ~(tap z-in new-set))
          =(~(tap z-by new-map-from-old) ~(tap z-by new-map))
      ==
::
++  test-ztree-marker-is-not-a-valid-runtime-leaf
  =/  empty-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) ~)
  =/  good-node=*  [(d 1) ~ ~]
  =/  good-node-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) good-node)
  =/  marker=*  %ztree
  =/  marker-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) marker)
  =/  marker-left-set=*  [(d 1) %ztree ~]
  =/  marker-right-set=*  [(d 1) ~ %ztree]
  =/  marker-left-set-as-zset=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) marker-left-set)
  =/  marker-right-set-as-zset=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) marker-right-set)
  =/  good-set-as-zset=(unit (z-set noun-digest:tip5:z))
    ((soft (z-set noun-digest:tip5:z)) good-node)
  =/  marker-left-map=*  [[(d 1) 10] %ztree ~]
  =/  marker-right-map=*  [[(d 1) 10] ~ %ztree]
  =/  marker-left-map-as-zmap=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) marker-left-map)
  =/  marker-right-map-as-zmap=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) marker-right-map)
  =/  good-map-node=*  [[(d 1) 10] ~ ~]
  =/  good-map-as-zmap=(unit (z-map noun-digest:tip5:z @))
    ((soft (z-map noun-digest:tip5:z @)) good-map-node)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  ?=(^ empty-as-ztree)
          ?=(^ good-node-as-ztree)
          ?=(~ marker-as-ztree)
          ?=(~ marker-left-set-as-zset)
          ?=(~ marker-right-set-as-zset)
          ?=(^ good-set-as-zset)
          ?=(~ marker-left-map-as-zmap)
          ?=(~ marker-right-map-as-zmap)
          ?=(^ good-map-as-zmap)
      ==
::
++  test-underlying-tree-tags-separate-z-and-h
  =/  zset=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  hset=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  zmap=(z-map noun-digest:tip5:z @)
    (~(put z-by *(z-map noun-digest:tip5:z @)) (d 3) 30)
  =/  hmap=(h-map noun-digest:tip5:z @)
    (~(put h-by *(h-map noun-digest:tip5:z @)) (d 3) 30)
  =/  empty-zset=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  =/  empty-hset=(h-set noun-digest:tip5:z)  *(h-set noun-digest:tip5:z)
  =/  empty-zmap=(z-map noun-digest:tip5:z @)  *(z-map noun-digest:tip5:z @)
  =/  empty-hmap=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  =/  zset-as-hset-tree=(unit (hset-tree noun-digest:tip5:z))
    ((soft (hset-tree noun-digest:tip5:z)) zset)
  =/  hset-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) hset)
  =/  empty-zset-as-hset-tree=(unit (hset-tree noun-digest:tip5:z))
    ((soft (hset-tree noun-digest:tip5:z)) empty-zset)
  =/  empty-hset-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) empty-hset)
  =/  zset-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) zset)
  =/  hset-as-hset-tree=(unit (hset-tree noun-digest:tip5:z))
    ((soft (hset-tree noun-digest:tip5:z)) hset)
  =/  zmap-as-hmap-tree=(unit (hmap-tree (pair noun-digest:tip5:z @)))
    ((soft (hmap-tree (pair noun-digest:tip5:z @))) zmap)
  =/  hmap-as-ztree=(unit (ztree (pair noun-digest:tip5:z @)))
    ((soft (ztree (pair noun-digest:tip5:z @))) hmap)
  =/  empty-zmap-as-hmap-tree=(unit (hmap-tree (pair noun-digest:tip5:z @)))
    ((soft (hmap-tree (pair noun-digest:tip5:z @))) empty-zmap)
  =/  empty-hmap-as-ztree=(unit (ztree (pair noun-digest:tip5:z @)))
    ((soft (ztree (pair noun-digest:tip5:z @))) empty-hmap)
  =/  zmap-as-ztree=(unit (ztree (pair noun-digest:tip5:z @)))
    ((soft (ztree (pair noun-digest:tip5:z @))) zmap)
  =/  hmap-as-hmap-tree=(unit (hmap-tree (pair noun-digest:tip5:z @)))
    ((soft (hmap-tree (pair noun-digest:tip5:z @))) hmap)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  ?=(~ zset-as-hset-tree)
          ?=(~ hset-as-ztree)
          ?=(~ empty-zset-as-hset-tree)
          ?=(~ empty-hset-as-ztree)
          ?=(^ zset-as-ztree)
          ?=(^ hset-as-hset-tree)
          ?=(~ zmap-as-hmap-tree)
          ?=(~ hmap-as-ztree)
          ?=(~ empty-zmap-as-hmap-tree)
          ?=(~ empty-hmap-as-ztree)
          ?=(^ zmap-as-ztree)
          ?=(^ hmap-as-hmap-tree)
      ==
::
++  test-z-engines-emit-null-leaves-not-ztree-markers
  =/  zset=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  zset-one-gone=(z-set noun-digest:tip5:z)
    (~(del z-in zset) (d 1))
  =/  zset-empty=(z-set noun-digest:tip5:z)
    (~(del z-in zset-one-gone) (d 2))
  =/  zmap=(z-map noun-digest:tip5:z @)
    %-  ~(gas z-by *(z-map noun-digest:tip5:z @))
    ~[[(d 1) 10] [(d 2) 20]]
  =/  zmap-one-gone=(z-map noun-digest:tip5:z @)
    (~(del z-by zmap) (d 1))
  =/  zmap-empty=(z-map noun-digest:tip5:z @)
    (~(del z-by zmap-one-gone) (d 2))
  =/  zset-empty-as-ztree=(unit (ztree noun-digest:tip5:z))
    ((soft (ztree noun-digest:tip5:z)) zset-empty)
  =/  zmap-empty-as-ztree=(unit (ztree (pair noun-digest:tip5:z @)))
    ((soft (ztree (pair noun-digest:tip5:z @))) zmap-empty)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y])
  !>  :*  =(~ zset-empty)
          =(~ zmap-empty)
          !=(%ztree zset-empty)
          !=(%ztree zmap-empty)
          ?=(^ zset-empty-as-ztree)
          ?=(^ zmap-empty-as-ztree)
      ==
::
++  test-h-map-and-h-set-tags-reject-direct-mixing
  =/  hset=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2)])
  =/  hmap=(h-map noun-digest:tip5:z @)
    (~(put h-by *(h-map noun-digest:tip5:z @)) (d 1) 10)
  =/  empty-hset=(h-set noun-digest:tip5:z)  *(h-set noun-digest:tip5:z)
  =/  empty-hmap=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  =/  null-value-map=(h-map noun-digest:tip5:z ~)
    (~(put h-by *(h-map noun-digest:tip5:z ~)) (d 9) ~)
  =/  key-set=(h-set noun-digest:tip5:z)  ~(key h-by hmap)
  =/  hset-as-hmap=(unit (h-map noun-digest:tip5:z @))
    ((soft (h-map noun-digest:tip5:z @)) hset)
  =/  hmap-as-hset=(unit (h-set noun-digest:tip5:z))
    ((soft (h-set noun-digest:tip5:z)) hmap)
  =/  empty-hset-as-hmap=(unit (h-map noun-digest:tip5:z @))
    ((soft (h-map noun-digest:tip5:z @)) empty-hset)
  =/  empty-hmap-as-hset=(unit (h-set noun-digest:tip5:z))
    ((soft (h-set noun-digest:tip5:z)) empty-hmap)
  =/  null-map-as-digest-list-set=(unit (h-set noun-digests:z))
    ((soft (h-set noun-digests:z)) null-value-map)
  =/  key-set-as-map=(unit (h-map noun-digest:tip5:z @))
    ((soft (h-map noun-digest:tip5:z @)) key-set)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  ?=(~ hset-as-hmap)
          ?=(~ hmap-as-hset)
          ?=(~ empty-hset-as-hmap)
          ?=(~ empty-hmap-as-hset)
          ?=(~ null-map-as-digest-list-set)
          ?=(~ key-set-as-map)
          ~(apt h-in key-set)
          (~(has h-in key-set) (d 1))
          =(1 ~(wyt h-in key-set))
      ==
::
++  test-h-map-read-write-delete-roundtrip
  =/  m=(h-map noun-digest:tip5:z @)
    %-  ~(gas h-by *(h-map noun-digest:tip5:z @))
    ~[[(d 1) 10] [(d 2) 20] [(d 3) 30] [(d 4) 40]]
  =/  initial-apt=?  ~(apt h-by m)
  =/  initial-val=@  (~(got h-by m) (d 2))
  =.  m  (~(put h-by m) (d 2) 22)
  =.  m  (~(del h-by m) (d 3))
  =/  legacy=(z-map noun-digest:tip5:z @)  (hz-molt m)
  %+  expect-eq
    !>([%.y 20 %.y %.y %.n 22])
  !>  :*  initial-apt
          initial-val
          ~(apt h-by m)
          (~(has h-by m) (d 2))
          (~(has h-by m) (d 3))
          (~(got z-by legacy) (d 2))
      ==
::
++  test-h-set-mip-jug-roundtrip
  =/  zset=(z-set noun-digest:tip5:z)
    (~(gas z-in *(z-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3)])
  =/  hset=(h-set noun-digest:tip5:z)  (zh-silt zset)
  =/  zset-back=(z-set noun-digest:tip5:z)  (hz-silt hset)
  ::
  =/  zmip=(z-mip noun-digest:tip5:z noun-digest:tip5:z noun-digest:tip5:z)
    =/  out=(z-mip noun-digest:tip5:z noun-digest:tip5:z noun-digest:tip5:z)
      *(z-mip noun-digest:tip5:z noun-digest:tip5:z noun-digest:tip5:z)
    =.  out  (~(put z-bi out) (d 1) (d 2) (d 12))
    (~(put z-bi out) (d 1) (d 3) (d 13))
  =/  hmip=(h-mip noun-digest:tip5:z noun-digest:tip5:z noun-digest:tip5:z)
    (zh-milt zmip)
  =/  inner=(h-map noun-digest:tip5:z noun-digest:tip5:z)
    (~(got h-by hmip) (d 1))
  =/  zmip-back=(z-mip noun-digest:tip5:z noun-digest:tip5:z noun-digest:tip5:z)
    (hz-milt hmip)
  ::
  =/  zjug=(z-jug noun-digest:tip5:z noun-digest:tip5:z)
    =/  out=(z-jug noun-digest:tip5:z noun-digest:tip5:z)
      *(z-jug noun-digest:tip5:z noun-digest:tip5:z)
    =.  out  (~(put z-ju out) (d 4) (d 5))
    (~(put z-ju out) (d 4) (d 6))
  =/  hjug=(h-jug noun-digest:tip5:z noun-digest:tip5:z)  (zh-jult zjug)
  =/  jug-set=(h-set noun-digest:tip5:z)  (~(get h-ju hjug) (d 4))
  =/  zjug-back=(z-jug noun-digest:tip5:z noun-digest:tip5:z)  (hz-jult hjug)
  ::
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y %.y %.y %.y %.y %.y %.y])
  !>  :*  =(3 ~(wyt z-in zset-back))
          (~(has z-in zset-back) (d 1))
          ~(apt h-in hset)
          ~(apt h-by hmip)
          ~(apt h-by inner)
          (~(has z-bi zmip-back) (d 1) (d 2))
          =((~(got z-bi zmip-back) (d 1) (d 3)) (d 13))
          ~(apt h-by hjug)
          ~(apt h-in jug-set)
          (~(has z-ju zjug-back) (d 4) (d 5))
          (~(has z-ju zjug-back) (d 4) (d 6))
      ==
::
++  test-mor-hip-uses-reversed-digest-limbs
  =/  a=noun-digest:tip5:z  [1 0 0 0 9]
  =/  b=noun-digest:tip5:z  [2 0 0 0 1]
  %+  expect-eq
    !>([%.y %.n %.n %.y])
  !>  :*  (gor-hip a b)
          (mor-hip a b)
          (mor-digests [a ~] [b ~])
          !=((gor-hip a b) (mor-hip a b))
      ==
::
++  test-hip-ordering-prefix-and-empty-boundaries
  =/  gor-high=noun-digest:tip5:z  [0 0 0 0 2]
  =/  gor-low=noun-digest:tip5:z   [99 99 99 99 1]
  =/  mor-high=noun-digest:tip5:z  [2 0 0 0 0]
  =/  mor-low=noun-digest:tip5:z   [1 99 99 99 99]
  =/  prefix=noun-digest:tip5:z  [1 2 3 4 5]
  =/  list-high=noun-digests:z  ~[prefix [0 0 0 0 7]]
  =/  list-low=noun-digests:z   ~[prefix [0 0 0 0 6]]
  =/  empty=noun-digests:z  ~
  %+  expect-eq
    !>([%.y %.n %.y %.n %.y %.y %.n %.y %.n %.n])
  !>  :*  (gor-hip gor-high gor-low)
          (gor-hip gor-low gor-high)
          (mor-hip mor-high mor-low)
          (mor-hip mor-low mor-high)
          (gor-hip list-high list-low)
          (mor-hip list-high list-low)
          (gor-hip empty gor-high)
          (gor-hip gor-high empty)
          (gor-hip empty empty)
          (mor-hip empty empty)
      ==
::
++  test-nested-digest-list-conversions-preserve-duplicates
  =/  k-a=noun-digests:z  (md 1 1)
  =/  k-b=noun-digests:z  (md 1 2)
  =/  k-c=noun-digests:z  (md 2 1)
  =/  k-d=noun-digests:z  (md 3 3)
  =/  zmip=(z-mip noun-digests:z noun-digests:z @)
    =/  out=(z-mip noun-digests:z noun-digests:z @)
      *(z-mip noun-digests:z noun-digests:z @)
    =.  out  (~(put z-bi out) k-a k-b 10)
    =.  out  (~(put z-bi out) k-a k-c 20)
    =.  out  (~(put z-bi out) k-a k-b 11)
    (~(put z-bi out) k-d k-b 30)
  =/  hmip=(h-mip noun-digests:z noun-digests:z @)  (zh-milt zmip)
  =/  zmip-back=(z-mip noun-digests:z noun-digests:z @)  (hz-milt hmip)
  =/  inner=(h-map noun-digests:z @)  (~(got h-by hmip) k-a)
  =/  zjug=(z-jug noun-digests:z noun-digests:z)
    =/  out=(z-jug noun-digests:z noun-digests:z)
      *(z-jug noun-digests:z noun-digests:z)
    =.  out  (~(put z-ju out) k-a k-b)
    =.  out  (~(put z-ju out) k-a k-c)
    =.  out  (~(put z-ju out) k-a k-b)
    (~(put z-ju out) k-d k-b)
  =/  hjug=(h-jug noun-digests:z noun-digests:z)  (zh-jult zjug)
  =/  zjug-back=(z-jug noun-digests:z noun-digests:z)  (hz-jult hjug)
  =/  hset=(h-set noun-digests:z)  (~(get h-ju hjug) k-a)
  %+  expect-eq
    !>([%.y %.y %.y %.y 11 20 30 2 %.y %.y %.y])
  !>  :*  =((hz-milt hmip) zmip)
          =((zh-milt zmip-back) hmip)
          =((hz-jult hjug) zjug)
          =((zh-jult zjug-back) hjug)
          (~(got h-by inner) k-b)
          (~(got h-by inner) k-c)
          (~(got h-bi hmip) k-d k-b)
          ~(wyt h-in hset)
          (~(has h-ju hjug) k-a k-b)
          (~(has h-ju hjug) k-a k-c)
          ~(apt h-by hmip)
      ==
::
++  test-h-map-union-preserves-apt
  =/  a=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 1) 1] [(d 2) 2] [(d 3) 3]])
  =/  b=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 3) 30] [(d 4) 4] [(d 5) 5]])
  =/  uni=(h-map noun-digest:tip5:z @)  (~(uni h-by a) b)
  %+  expect-eq
    !>([%.y %.y %.y 5 %.y %.y])
  !>  :*  ~(apt h-by a)
          ~(apt h-by b)
          ~(apt h-by uni)
          ~(wyt h-by uni)
          (~(has h-by uni) (d 1))
          (~(has h-by uni) (d 5))
      ==
::
++  test-h-map-intersection-preserves-apt
  =/  a=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 1) 1] [(d 2) 2] [(d 3) 3]])
  =/  b=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 3) 30] [(d 4) 4] [(d 5) 5]])
  =/  int=(h-map noun-digest:tip5:z @)  (~(int h-by a) b)
  %+  expect-eq
    !>([%.y %.y %.y 1 %.y %.n %.n])
  !>  :*  ~(apt h-by a)
          ~(apt h-by b)
          ~(apt h-by int)
          ~(wyt h-by int)
          (~(has h-by int) (d 3))
          (~(has h-by int) (d 2))
          (~(has h-by int) (d 4))
      ==
::
++  test-h-map-difference-preserves-apt
  =/  a=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 1) 1] [(d 2) 2] [(d 3) 3]])
  =/  b=(h-map noun-digest:tip5:z @)
    (~(gas h-by *(h-map noun-digest:tip5:z @)) ~[[(d 3) 30] [(d 4) 4] [(d 5) 5]])
  =/  dif=(h-map noun-digest:tip5:z @)  (~(dif h-by a) b)
  %+  expect-eq
    !>([%.y %.y %.y 2 %.y %.y %.n])
  !>  :*  ~(apt h-by a)
          ~(apt h-by b)
          ~(apt h-by dif)
          ~(wyt h-by dif)
          (~(has h-by dif) (d 1))
          (~(has h-by dif) (d 2))
          (~(has h-by dif) (d 3))
      ==
::
++  test-h-set-union-preserves-apt
  =/  sa=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3)])
  =/  sb=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 3) (d 4) (d 5)])
  =/  suni=(h-set noun-digest:tip5:z)  (~(uni h-in sa) sb)
  %+  expect-eq
    !>([%.y %.y %.y 5 %.y %.y])
  !>  :*  ~(apt h-in sa)
          ~(apt h-in sb)
          ~(apt h-in suni)
          ~(wyt h-in suni)
          (~(has h-in suni) (d 1))
          (~(has h-in suni) (d 5))
      ==
::
++  test-h-set-intersection-preserves-apt
  =/  sa=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3)])
  =/  sb=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 3) (d 4) (d 5)])
  =/  sint=(h-set noun-digest:tip5:z)  (~(int h-in sa) sb)
  %+  expect-eq
    !>([%.y %.y %.y 1 %.y %.n %.n])
  !>  :*  ~(apt h-in sa)
          ~(apt h-in sb)
          ~(apt h-in sint)
          ~(wyt h-in sint)
          (~(has h-in sint) (d 3))
          (~(has h-in sint) (d 2))
          (~(has h-in sint) (d 4))
      ==
::
++  test-h-set-difference-preserves-apt
  =/  sa=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 1) (d 2) (d 3)])
  =/  sb=(h-set noun-digest:tip5:z)
    (~(gas h-in *(h-set noun-digest:tip5:z)) ~[(d 3) (d 4) (d 5)])
  =/  sdif=(h-set noun-digest:tip5:z)  (~(dif h-in sa) sb)
  %+  expect-eq
    !>([%.y %.y %.y 2 %.y %.y %.n])
  !>  :*  ~(apt h-in sa)
          ~(apt h-in sb)
          ~(apt h-in sdif)
          ~(wyt h-in sdif)
          (~(has h-in sdif) (d 1))
          (~(has h-in sdif) (d 2))
          (~(has h-in sdif) (d 3))
      ==
::  +|  %random-differential
::
::    each helper threads a counter through (hash-noun-varlen [seed ctr])
::    to draw an op and a key from a deterministic stream. the key space is
::    intentionally small (key-mod) so duplicate keys force balance
::    rotations and re-insertion paths. after every op we assert
::      ?&  ~(apt h-by hm)
::          =((hz-* hm) zm)
::          (~(has h-by hm) <every inserted key>) = (~(has z-by zm) ...)
::      ==
::    on failure the helper crashes with the failing op index plus the
::    last drawn op/key so the prefix can be promoted to a regression.
::
++  step-count  256
++  key-mod  16
::
++  rand-token
  |=  [seed=@uv ctr=@]
  ^-  [tok=@ key=noun-digest:tip5:z]
  =/  digest=noun-digest:tip5:z  (hash-noun-varlen:tip5:z [seed ctr])
  [(digest-to-atom:tip5:z digest) digest]
::
::  small key space forces collisions; we reuse the high digest as a fresh
::  unique key when the op needs one outside the collision pool.
++  draw-key-small
  |=  [seed=@uv ctr=@]
  ^-  noun-digest:tip5:z
  =+  ^=  rt  (rand-token seed ctr)
  (atom-to-digest:tip5:z `@ux`(mod tok.rt key-mod))
::
++  draw-key-fresh
  |=  [seed=@uv ctr=@]
  ^-  noun-digest:tip5:z
  =+  ^=  rt  (rand-token seed ctr)
  key.rt
::
++  draw-value
  |=  [seed=@uv ctr=@]
  ^-  @
  =+  ^=  rt  (rand-token seed +(ctr))
  (mod tok.rt 1.000.003)
::
::  pick one of {put, del, gas, uni, int, dif} weighted toward put/del
::  so the tree actually grows. uni/int/dif rebuild the right-hand side
::  from a fresh draw so we exercise structural ops on non-overlapping
::  but realistic shapes.
++  draw-map-op
  |=  [seed=@uv ctr=@]
  ^-  @
  =+  ^=  rt  (rand-token seed (add ctr 7))
  =/  bucket=@  (mod tok.rt 16)
  ?:  (lth bucket 5)   %0  :: put
  ?:  (lth bucket 9)   %1  :: del
  ?:  (lth bucket 11)  %2  :: gas
  ?:  (lth bucket 13)  %3  :: uni
  ?:  (lth bucket 15)  %4  :: int
  %5                       :: dif
::
::  build a side map for the binary ops without leaking through to the
::  main accumulator; size n stays small so int/dif have meaningful
::  overlap with the running container.
++  side-map
  |=  [seed=@uv ctr=@ size=@]
  ^-  [hm=(h-map noun-digest:tip5:z @) zm=(z-map noun-digest:tip5:z @)]
  =/  i=@  0
  =/  hm=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  =/  zm=(z-map noun-digest:tip5:z @)  *(z-map noun-digest:tip5:z @)
  |-
  ?:  =(i size)  [hm zm]
  =/  k=noun-digest:tip5:z  (draw-key-small seed (add ctr i))
  =/  v=@  (draw-value seed (add ctr i))
  $(i +(i), hm (~(put h-by hm) k v), zm (~(put z-by zm) k v))
::
++  side-set
  |=  [seed=@uv ctr=@ size=@]
  ^-  [hs=(h-set noun-digest:tip5:z) zs=(z-set noun-digest:tip5:z)]
  =/  i=@  0
  =/  hs=(h-set noun-digest:tip5:z)  *(h-set noun-digest:tip5:z)
  =/  zs=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  |-
  ?:  =(i size)  [hs zs]
  =/  k=noun-digest:tip5:z  (draw-key-small seed (add ctr i))
  $(i +(i), hs (~(put h-in hs) k), zs (~(put z-in zs) k))
::
::  drive `n` ops against parallel h-map and z-map. on first divergence
::  abort loudly with the failing op id; otherwise return %.y.
++  run-map-ops
  |=  [seed=@uv n=@]
  ^-  ?
  =/  hm=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  =/  zm=(z-map noun-digest:tip5:z @)  *(z-map noun-digest:tip5:z @)
  =/  inserted=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  =/  ctr=@  0
  |-
  ?:  =(ctr n)
    ?.  ~(apt h-by hm)  ~&  [%map-final-apt-failed seed]  !!
    ?.  =((hz-molt hm) zm)  ~&  [%map-final-mismatch seed]  !!
    ?.  =(~(wyt h-by hm) ~(wyt z-by zm))  ~&  [%map-final-size-mismatch seed]  !!
    ::  probe every inserted key
    =/  remaining=(list noun-digest:tip5:z)  ~(tap z-in inserted)
    |-  ^-  ?
    ?~  remaining  %.y
    ?.  =((~(has h-by hm) i.remaining) (~(has z-by zm) i.remaining))
      ~&  [%map-final-has-mismatch seed key=i.remaining]  !!
    ?:  (~(has h-by hm) i.remaining)
      ?.  =((~(got h-by hm) i.remaining) (~(got z-by zm) i.remaining))
        ~&  [%map-final-got-mismatch seed key=i.remaining]  !!
      $(remaining t.remaining)
    $(remaining t.remaining)
  =/  op=@  (draw-map-op seed ctr)
  =/  k=noun-digest:tip5:z  (draw-key-small seed ctr)
  =/  v=@  (draw-value seed ctr)
  =/  ins  (~(put z-in inserted) k)
  =/  pair
    ?+  op  [hm zm]
        %0
      [(~(put h-by hm) k v) (~(put z-by zm) k v)]
    ::
        %1
      [(~(del h-by hm) k) (~(del z-by zm) k)]
    ::
        %2
      =/  extras
        ^-  (list [noun-digest:tip5:z @])
        :~  [k v]
            [(draw-key-small seed (add ctr 1)) (draw-value seed (add ctr 1))]
            [(draw-key-small seed (add ctr 2)) (draw-value seed (add ctr 2))]
            [(draw-key-small seed (add ctr 3)) (draw-value seed (add ctr 3))]
        ==
      [(~(gas h-by hm) extras) (~(gas z-by zm) extras)]
    ::
        %3
      =+  ^=  side  (side-map seed (add ctr 41) 6)
      [(~(uni h-by hm) hm.side) (~(uni z-by zm) zm.side)]
    ::
        %4
      =+  ^=  side  (side-map seed (add ctr 113) 6)
      [(~(int h-by hm) hm.side) (~(int z-by zm) zm.side)]
    ::
        %5
      =+  ^=  side  (side-map seed (add ctr 199) 6)
      [(~(dif h-by hm) hm.side) (~(dif z-by zm) zm.side)]
    ==
  =/  hm-next=(h-map noun-digest:tip5:z @)  -.pair
  =/  zm-next=(z-map noun-digest:tip5:z @)  +.pair
  =/  step-ok=?
    ?&  ~(apt h-by hm-next)
        =((hz-molt hm-next) zm-next)
        =(~(wyt h-by hm-next) ~(wyt z-by zm-next))
    ==
  ?.  step-ok
    ~&  [%map-step-failed seed step=ctr op=op key=k val=v]  !!
  $(ctr +(ctr), hm hm-next, zm zm-next, inserted ins)
::
++  draw-set-op
  |=  [seed=@uv ctr=@]
  ^-  @
  =+  ^=  rt  (rand-token seed (add ctr 13))
  =/  bucket=@  (mod tok.rt 16)
  ?:  (lth bucket 6)   %0  :: put
  ?:  (lth bucket 10)  %1  :: del
  ?:  (lth bucket 12)  %2  :: gas
  ?:  (lth bucket 14)  %3  :: uni
  ?:  (lth bucket 15)  %4  :: int
  %5                       :: dif
::
++  run-set-ops
  |=  [seed=@uv n=@]
  ^-  ?
  =/  hs=(h-set noun-digest:tip5:z)  *(h-set noun-digest:tip5:z)
  =/  zs=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  =/  inserted=(z-set noun-digest:tip5:z)  *(z-set noun-digest:tip5:z)
  =/  ctr=@  0
  |-
  ?:  =(ctr n)
    ?.  ~(apt h-in hs)  ~&  [%set-final-apt-failed seed]  !!
    ?.  =((hz-silt hs) zs)  ~&  [%set-final-mismatch seed]  !!
    ?.  =(~(wyt h-in hs) ~(wyt z-in zs))  ~&  [%set-final-size-mismatch seed]  !!
    =/  remaining=(list noun-digest:tip5:z)  ~(tap z-in inserted)
    |-  ^-  ?
    ?~  remaining  %.y
    ?.  =((~(has h-in hs) i.remaining) (~(has z-in zs) i.remaining))
      ~&  [%set-has-mismatch seed key=i.remaining]  !!
    $(remaining t.remaining)
  =/  op=@  (draw-set-op seed ctr)
  =/  k=noun-digest:tip5:z  (draw-key-small seed ctr)
  =/  ins  (~(put z-in inserted) k)
  =/  pair
    ?+  op  [hs zs]
        %0
      [(~(put h-in hs) k) (~(put z-in zs) k)]
    ::
        %1
      [(~(del h-in hs) k) (~(del z-in zs) k)]
    ::
        %2
      =/  ks
        ^-  (list noun-digest:tip5:z)
        :~  k
            (draw-key-small seed (add ctr 1))
            (draw-key-small seed (add ctr 2))
            (draw-key-small seed (add ctr 3))
        ==
      [(~(gas h-in hs) ks) (~(gas z-in zs) ks)]
    ::
        %3
      =+  ^=  side  (side-set seed (add ctr 17) 6)
      [(~(uni h-in hs) hs.side) (~(uni z-in zs) zs.side)]
    ::
        %4
      =+  ^=  side  (side-set seed (add ctr 37) 6)
      [(~(int h-in hs) hs.side) (~(int z-in zs) zs.side)]
    ::
        %5
      =+  ^=  side  (side-set seed (add ctr 67) 6)
      [(~(dif h-in hs) hs.side) (~(dif z-in zs) zs.side)]
    ==
  =/  hs-next=(h-set noun-digest:tip5:z)  -.pair
  =/  zs-next=(z-set noun-digest:tip5:z)  +.pair
  =/  step-ok=?
    ?&  ~(apt h-in hs-next)
        =((hz-silt hs-next) zs-next)
        =(~(wyt h-in hs-next) ~(wyt z-in zs-next))
    ==
  ?.  step-ok
    ~&  [%set-step-failed seed step=ctr op=op key=k]  !!
  $(ctr +(ctr), hs hs-next, zs zs-next, inserted ins)
::
++  draw-jug-op
  |=  [seed=@uv ctr=@]
  ^-  @
  =+  ^=  rt  (rand-token seed (add ctr 23))
  ?:  (lth (mod tok.rt 8) 5)  %0  :: put
  %1                                :: del
::
++  run-jug-ops
  |=  [seed=@uv n=@]
  ^-  ?
  =/  hj=(h-jug noun-digest:tip5:z noun-digest:tip5:z)
    *(h-jug noun-digest:tip5:z noun-digest:tip5:z)
  =/  zj=(z-jug noun-digest:tip5:z noun-digest:tip5:z)
    *(z-jug noun-digest:tip5:z noun-digest:tip5:z)
  =/  inserted=(list [noun-digest:tip5:z noun-digest:tip5:z])  ~
  =/  ctr=@  0
  |-
  ?:  =(ctr n)
    ?.  ~(apt h-by hj)  ~&  [%jug-final-apt-failed seed]  !!
    ?.  =((hz-jult hj) zj)  ~&  [%jug-final-mismatch seed]  !!
    =/  remaining  inserted
    |-  ^-  ?
    ?~  remaining  %.y
    =/  pq=[noun-digest:tip5:z noun-digest:tip5:z]  i.remaining
    ?.  =((~(has h-ju hj) -.pq +.pq) (~(has z-ju zj) -.pq +.pq))
      ~&  [%jug-has-mismatch seed entry=pq]  !!
    $(remaining t.remaining)
  =/  op=@  (draw-jug-op seed ctr)
  =/  k1=noun-digest:tip5:z  (draw-key-small seed ctr)
  =/  k2=noun-digest:tip5:z  (draw-key-small seed (add ctr 31))
  =/  pair
    ?+  op  [hj zj]
        %0
      [(~(put h-ju hj) k1 k2) (~(put z-ju zj) k1 k2)]
    ::
        %1
      [(~(del h-ju hj) k1 k2) (~(del z-ju zj) k1 k2)]
    ==
  =/  hj-next=(h-jug noun-digest:tip5:z noun-digest:tip5:z)  -.pair
  =/  zj-next=(z-jug noun-digest:tip5:z noun-digest:tip5:z)  +.pair
  =/  step-ok=?
    ?&  ~(apt h-by hj-next)
        =((hz-jult hj-next) zj-next)
    ==
  ?.  step-ok
    ~&  [%jug-step-failed seed step=ctr op=op k1=k1 k2=k2]  !!
  $(ctr +(ctr), hj hj-next, zj zj-next, inserted [[k1 k2] inserted])
::
++  draw-mip-op
  |=  [seed=@uv ctr=@]
  ^-  @
  =+  ^=  rt  (rand-token seed (add ctr 29))
  ?:  (lth (mod tok.rt 8) 5)  %0  :: put
  %1                                :: del
::
++  run-mip-ops
  |=  [seed=@uv n=@]
  ^-  ?
  =/  hm=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)
    *(h-mip noun-digest:tip5:z noun-digest:tip5:z @)
  =/  zm=(z-mip noun-digest:tip5:z noun-digest:tip5:z @)
    *(z-mip noun-digest:tip5:z noun-digest:tip5:z @)
  =/  inserted=(list [noun-digest:tip5:z noun-digest:tip5:z])  ~
  =/  ctr=@  0
  |-
  ?:  =(ctr n)
    ?.  ~(apt h-by hm)  ~&  [%mip-final-apt-failed seed]  !!
    ?.  =((hz-milt hm) zm)  ~&  [%mip-final-mismatch seed]  !!
    =/  remaining  inserted
    |-  ^-  ?
    ?~  remaining  %.y
    =/  pq=[noun-digest:tip5:z noun-digest:tip5:z]  i.remaining
    ?.  =((~(has h-bi hm) -.pq +.pq) (~(has z-bi zm) -.pq +.pq))
      ~&  [%mip-has-mismatch seed entry=pq]  !!
    $(remaining t.remaining)
  =/  op=@  (draw-mip-op seed ctr)
  =/  k1=noun-digest:tip5:z  (draw-key-small seed ctr)
  =/  k2=noun-digest:tip5:z  (draw-key-small seed (add ctr 43))
  =/  v=@  (draw-value seed ctr)
  =/  pair
    ?+  op  [hm zm]
        %0
      [(~(put h-bi hm) k1 k2 v) (~(put z-bi zm) k1 k2 v)]
    ::
        %1
      [(~(del h-bi hm) k1 k2) (~(del z-bi zm) k1 k2)]
    ==
  =/  hm-next=(h-mip noun-digest:tip5:z noun-digest:tip5:z @)  -.pair
  =/  zm-next=(z-mip noun-digest:tip5:z noun-digest:tip5:z @)  +.pair
  =/  step-ok=?
    ?&  ~(apt h-by hm-next)
        =((hz-milt hm-next) zm-next)
    ==
  ?.  step-ok
    ~&  [%mip-step-failed seed step=ctr op=op k1=k1 k2=k2 v=v]  !!
  $(ctr +(ctr), hm hm-next, zm zm-next, inserted [[k1 k2] inserted])
::
::  the seed list deliberately includes a small constant, a far-future
::  constant, and two memorable big seeds so reviewers can pin a
::  regression by adding the seed that found it without changing the
::  helper. step-count is bumped here, not in run-*.
++  random-seeds
  ^-  (list @uv)
  ~[0v1 0v2 0v3 0v4 0v5.cafeb 0v6.beef5]
::
++  test-h-map-random-ops-match-z-map
  =/  seeds=(list @uv)  random-seeds
  %+  expect-eq
    !>(~[%.y %.y %.y %.y %.y %.y])
  !>  %+  turn  seeds
      |=  seed=@uv
      (run-map-ops seed step-count)
::
++  test-h-set-random-ops-match-z-set
  =/  seeds=(list @uv)  random-seeds
  %+  expect-eq
    !>(~[%.y %.y %.y %.y %.y %.y])
  !>  %+  turn  seeds
      |=  seed=@uv
      (run-set-ops seed step-count)
::
++  test-h-jug-random-ops-match-z-jug
  =/  seeds=(list @uv)  random-seeds
  %+  expect-eq
    !>(~[%.y %.y %.y %.y %.y %.y])
  !>  %+  turn  seeds
      |=  seed=@uv
      (run-jug-ops seed step-count)
::
++  test-h-mip-random-ops-match-z-mip
  =/  seeds=(list @uv)  random-seeds
  %+  expect-eq
    !>(~[%.y %.y %.y %.y %.y %.y])
  !>  %+  turn  seeds
      |=  seed=@uv
      (run-mip-ops seed step-count)
::
::    h-zoon singleton digest-list rejection oracle.
::
::    `hashed = $^(noun-digests:z noun-digest:tip5:z)` is an untagged
::    union dispatched by shape. a single tip5 digest `d` and the
::    one-element list `~[d]` are distinct nouns, but both normalize to
::    the same digest list. `h-*` containers now reject the ambiguous
::    singleton-list form at normalization, insertion, conversion, and
::    validation boundaries.
::
::    the `(z-set hashed)` control keeps raw-noun ordering. it may hold
::    both shapes, then `zh-*` must reject the singleton-list key when
::    crossing into h-container semantics.
::
++  test-hashed-singleton-list-rejected-by-normalizer
  =/  one=noun-digest:tip5:z  (d 17)
  =/  lst=noun-digests:z      ~[one]
  ;:  weld
    %+  expect-eq
      !>([%.y %.n])
    !>  :*  !=(one lst)
            =((hashed-to-digests one) [one ~])
        ==
  ::
    %+  expect-fail  |.((hashed-to-digests lst))  ~
    %+  expect-fail  |.((gor-hip one lst))  ~
    %+  expect-fail  |.((gor-hip lst one))  ~
    %+  expect-fail  |.((mor-hip one lst))  ~
    %+  expect-fail  |.((mor-hip lst one))  ~
  ==
::
++  test-h-set-hashed-rejects-singleton-list-insertion
  =/  one=noun-digest:tip5:z  (d 17)
  =/  lst=noun-digests:z      ~[one]
  =/  empty=(h-set hashed)    *(h-set hashed)
  =/  s1=(h-set hashed)       (~(put h-in empty) one)
  ;:  weld
    %+  expect-eq
      !>([%.y 1 %.y])
    !>  :*  ~(apt h-in s1)
            ~(wyt h-in s1)
            (~(has h-in s1) one)
        ==
  ::
    %+  expect-fail  |.((~(put h-in empty) lst))  ~
    %+  expect-fail  |.((~(put h-in s1) lst))  ~
  ==
::
++  test-h-map-and-zh-conversions-reject-singleton-list
  =/  one=noun-digest:tip5:z  (d 42)
  =/  lst=noun-digests:z      ~[one]
  =/  empty-map=(h-map hashed @)  *(h-map hashed @)
  =/  good-map=(h-map hashed @)   (~(put h-by empty-map) one 7)
  =/  zset=(z-set hashed)         (~(put z-in *(z-set hashed)) lst)
  =/  zmap=(z-map hashed @)       (~(put z-by *(z-map hashed @)) lst 7)
  ;:  weld
    %+  expect-eq
      !>([%.y 7])
    !>  :*  ~(apt h-by good-map)
            (~(got h-by good-map) one)
        ==
  ::
    %+  expect-fail  |.((~(put h-by empty-map) lst 7))  ~
    %+  expect-fail  |.((~(put h-by good-map) lst 8))  ~
    %+  expect-fail  |.((zh-silt zset))  ~
    %+  expect-fail  |.((zh-molt zmap))  ~
  ==
::
++  test-hashed-non-singleton-list-remains-valid
  =/  one=noun-digest:tip5:z   (d 42)
  =/  two=noun-digest:tip5:z   (d 43)
  =/  pair=noun-digests:z      ~[one two]
  =/  hset=(h-set hashed)      (~(put h-in *(h-set hashed)) pair)
  =/  hmap=(h-map hashed @)    (~(put h-by *(h-map hashed @)) pair 99)
  =/  zset=(z-set hashed)      (~(put z-in *(z-set hashed)) pair)
  =/  zmap=(z-map hashed @)    (~(put z-by *(z-map hashed @)) pair 99)
  ;:  weld
    %+  expect-eq
      !>([pair %.y %.y %.y 99 %.y %.y])
    !>  :*  (hashed-to-digests pair)
            ~(apt h-in hset)
            (~(has h-in hset) pair)
            ~(apt h-by hmap)
            (~(got h-by hmap) pair)
            =((zh-silt zset) hset)
            =((zh-molt zmap) hmap)
        ==
  ==
::
++  test-hashed-singleton-list-rejected-inside-prebuilt-h-containers
  =/  root=noun-digest:tip5:z      (d 64)
  =/  bad=noun-digests:z           ~[(d 65)]
  =/  bad-left-set=(hset-tree hashed)  [root [bad %hset %hset] %hset]
  =/  bad-right-set=(hset-tree hashed)  [root %hset [bad %hset %hset]]
  =/  bad-left-map=(hmap-tree (pair hashed @))  [[root 1] [[bad 2] %hmap %hmap] %hmap]
  =/  bad-right-map=(hmap-tree (pair hashed @))  [[root 1] %hmap [[bad 2] %hmap %hmap]]
  ;:  weld
    %+  expect-fail  |.((apt-hashed-set bad-left-set))  ~
    %+  expect-fail  |.((apt-hashed-set bad-right-set))  ~
    %+  expect-fail  |.((apt-hashed-map bad-left-map))  ~
    %+  expect-fail  |.((apt-hashed-map bad-right-map))  ~
  ==
::
++  test-h-set-intersection-rejects-singleton-list-progress-hazard
  =/  one=noun-digest:tip5:z   (d 17)
  =/  bad=noun-digests:z       ~[one]
  =/  direct=(h-set hashed)    (~(put h-in *(h-set hashed)) one)
  =/  singleton=(hset-tree hashed)  [bad %hset %hset]
  ;:  weld
    %+  expect-fail  |.((~(int h-in direct) singleton))  ~
    %+  expect-fail  |.((~(int h-in singleton) direct))  ~
    %+  expect-fail  |.((~(uni h-in direct) singleton))  ~
    %+  expect-fail  |.((~(dif h-in direct) singleton))  ~
  ==
::
++  test-z-set-hashed-mixed-shapes-stay-consistent-control
  ::    the legacy (z-set hashed) uses raw-noun `gor`, which is
  ::    a strict total order on distinct nouns. `d` and `~[d]` become
  ::    two well-ordered keys: apt holds, both are findable, the tree
  ::    is insertion-order independent, and set difference is correct.
  =/  one=noun-digest:tip5:z  (d 17)
  =/  lst=noun-digests:z      ~[one]
  =/  empty=(z-set hashed)    *(z-set hashed)
  =/  s2=(z-set hashed)       (~(put z-in (~(put z-in empty) one)) lst)
  =/  s2-flip=(z-set hashed)  (~(put z-in (~(put z-in empty) lst)) one)
  =/  diff=(z-set hashed)     (~(dif z-in s2) s2-flip)
  %+  expect-eq
    !>([%.y 2 %.y %.y %.y %.y])
  !>  :*  ~(apt z-in s2)        ::  holds
          ~(wyt z-in s2)
          (~(has z-in s2) one)  ::  inserted key remains findable
          (~(has z-in s2) lst)
          =(s2 s2-flip)         ::  insertion-order independent
          =(empty diff)         ::  set difference is correct
      ==
::  +|  %large-scale-int-dif
::
::    int/dif pinned against a full benchmark-scale container.
::    the 10.240-key big map/set uses realistic digest keys
::    (hash-noun-varlen, matching tests/dumb/mod/benchmarks/
::    h-zoon-hot-path), so large-tree balance and gor-hip ordering
::    are exercised, not a degenerate ordinal fixture. a 48-item
::    operand (32 keys shared with big + 16 disjoint) drives int/dif.
::
::    int/dif are membership ops: convert the h-* result with hz-*
::    and assert exact noun-equality with the z-* twin. the forward
::    op on each is wrapped in ~>(%bout ..) with a ~& label for
::    isolated jet-vs-interpreter timing.
::
++  big-seed  `@uv`0v1
++  big-count  10.240
++  small-overlap  32
++  small-fresh  16
::
++  big-key
  |=  i=@
  ^-  noun-digest:tip5:z
  (hash-noun-varlen:tip5:z [big-seed i])
::
::  disjoint from every big-key: distinct hash preimage.
++  fresh-key
  |=  i=@
  ^-  noun-digest:tip5:z
  (hash-noun-varlen:tip5:z [big-seed (add big-count +(i))])
::
++  big-keys
  ^-  (list noun-digest:tip5:z)
  =/  i=@  0
  =|  acc=(list noun-digest:tip5:z)
  |-  ^+  acc
  ?:  =(i big-count)  acc
  $(i +(i), acc [(big-key i) acc])
::
++  big-pairs
  ^-  (list [noun-digest:tip5:z @])
  =/  i=@  0
  =|  acc=(list [noun-digest:tip5:z @])
  |-  ^+  acc
  ?:  =(i big-count)  acc
  $(i +(i), acc [[(big-key i) +(i)] acc])
::
::  overlap keys carry distinct values from big so int value routing
::  is actually exercised, not trivially matched.
++  small-pairs
  ^-  (list [noun-digest:tip5:z @])
  =/  overlap=(list [noun-digest:tip5:z @])
    =/  i=@  0
    =|  acc=(list [noun-digest:tip5:z @])
    |-  ^+  acc
    ?:  =(i small-overlap)  acc
    $(i +(i), acc [[(big-key (mul i 320)) (add 100.000 i)] acc])
  =/  fresh=(list [noun-digest:tip5:z @])
    =/  j=@  0
    =|  acc=(list [noun-digest:tip5:z @])
    |-  ^+  acc
    ?:  =(j small-fresh)  acc
    $(j +(j), acc [[(fresh-key j) (add 200.000 j)] acc])
  (weld overlap fresh)
::
++  small-keys
  ^-  (list noun-digest:tip5:z)
  (turn small-pairs |=([k=noun-digest:tip5:z v=@] k))
::
++  big-h-map
  ^-  (h-map noun-digest:tip5:z @)
  (~(gas h-by *(h-map noun-digest:tip5:z @)) big-pairs)
::
++  big-z-map
  ^-  (z-map noun-digest:tip5:z @)
  (~(gas z-by *(z-map noun-digest:tip5:z @)) big-pairs)
::
++  big-h-set
  ^-  (h-set noun-digest:tip5:z)
  (~(gas h-in *(h-set noun-digest:tip5:z)) big-keys)
::
++  big-z-set
  ^-  (z-set noun-digest:tip5:z)
  (~(gas z-in *(z-set noun-digest:tip5:z)) big-keys)
::
++  small-h-map
  ^-  (h-map noun-digest:tip5:z @)
  (~(gas h-by *(h-map noun-digest:tip5:z @)) small-pairs)
::
++  small-z-map
  ^-  (z-map noun-digest:tip5:z @)
  (~(gas z-by *(z-map noun-digest:tip5:z @)) small-pairs)
::
++  small-h-set
  ^-  (h-set noun-digest:tip5:z)
  (~(gas h-in *(h-set noun-digest:tip5:z)) small-keys)
::
++  small-z-set
  ^-  (z-set noun-digest:tip5:z)
  (~(gas z-in *(z-set noun-digest:tip5:z)) small-keys)
::
++  test-h-map-int-large-against-small
  =/  hb=(h-map noun-digest:tip5:z @)  big-h-map
  =/  zb=(z-map noun-digest:tip5:z @)  big-z-map
  =/  hs=(h-map noun-digest:tip5:z @)  small-h-map
  =/  zs=(z-map noun-digest:tip5:z @)  small-z-map
  ~&  %timing-h-map-int
  =/  h-int=(h-map noun-digest:tip5:z @)  ~>(%bout (~(int h-by hb) hs))
  ~&  %timing-z-map-int
  =/  z-int=(z-map noun-digest:tip5:z @)  ~>(%bout (~(int z-by zb) zs))
  =/  h-int-rev=(h-map noun-digest:tip5:z @)  (~(int h-by hs) hb)
  =/  z-int-rev=(z-map noun-digest:tip5:z @)  (~(int z-by zs) zb)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y 32 32])
  !>  :*  ~(apt h-by hb)
          ~(apt h-by h-int)
          ~(apt h-by h-int-rev)
          =((hz-molt h-int) z-int)
          =((hz-molt h-int-rev) z-int-rev)
          ~(wyt h-by h-int)
          ~(wyt h-by h-int-rev)
      ==
::
++  test-h-map-dif-large-against-small
  =/  hb=(h-map noun-digest:tip5:z @)  big-h-map
  =/  zb=(z-map noun-digest:tip5:z @)  big-z-map
  =/  hs=(h-map noun-digest:tip5:z @)  small-h-map
  =/  zs=(z-map noun-digest:tip5:z @)  small-z-map
  ~&  %timing-h-map-dif
  =/  h-dif=(h-map noun-digest:tip5:z @)  ~>(%bout (~(dif h-by hb) hs))
  ~&  %timing-z-map-dif
  =/  z-dif=(z-map noun-digest:tip5:z @)  ~>(%bout (~(dif z-by zb) zs))
  =/  h-dif-rev=(h-map noun-digest:tip5:z @)  (~(dif h-by hs) hb)
  =/  z-dif-rev=(z-map noun-digest:tip5:z @)  (~(dif z-by zs) zb)
  %+  expect-eq
    ::  big\small drops the 32 shared keys; small\big keeps the 16 fresh.
    !>([%.y %.y %.y %.y %.y 10.208 16])
  !>  :*  ~(apt h-by h-dif)
          ~(apt h-by h-dif-rev)
          =((hz-molt h-dif) z-dif)
          =((hz-molt h-dif-rev) z-dif-rev)
          =(~(wyt h-by h-dif) ~(wyt z-by z-dif))
          ~(wyt h-by h-dif)
          ~(wyt h-by h-dif-rev)
      ==
::
++  test-h-set-int-large-against-small
  =/  hb=(h-set noun-digest:tip5:z)  big-h-set
  =/  zb=(z-set noun-digest:tip5:z)  big-z-set
  =/  hs=(h-set noun-digest:tip5:z)  small-h-set
  =/  zs=(z-set noun-digest:tip5:z)  small-z-set
  ~&  %timing-h-set-int
  =/  h-int=(h-set noun-digest:tip5:z)  ~>(%bout (~(int h-in hb) hs))
  ~&  %timing-z-set-int
  =/  z-int=(z-set noun-digest:tip5:z)  ~>(%bout (~(int z-in zb) zs))
  =/  h-int-rev=(h-set noun-digest:tip5:z)  (~(int h-in hs) hb)
  =/  z-int-rev=(z-set noun-digest:tip5:z)  (~(int z-in zs) zb)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y 32 32])
  !>  :*  ~(apt h-in hb)
          ~(apt h-in h-int)
          ~(apt h-in h-int-rev)
          =((hz-silt h-int) z-int)
          =((hz-silt h-int-rev) z-int-rev)
          ~(wyt h-in h-int)
          ~(wyt h-in h-int-rev)
      ==
::
++  test-h-set-dif-large-against-small
  =/  hb=(h-set noun-digest:tip5:z)  big-h-set
  =/  zb=(z-set noun-digest:tip5:z)  big-z-set
  =/  hs=(h-set noun-digest:tip5:z)  small-h-set
  =/  zs=(z-set noun-digest:tip5:z)  small-z-set
  ~&  %timing-h-set-dif
  =/  h-dif=(h-set noun-digest:tip5:z)  ~>(%bout (~(dif h-in hb) hs))
  ~&  %timing-z-set-dif
  =/  z-dif=(z-set noun-digest:tip5:z)  ~>(%bout (~(dif z-in zb) zs))
  =/  h-dif-rev=(h-set noun-digest:tip5:z)  (~(dif h-in hs) hb)
  =/  z-dif-rev=(z-set noun-digest:tip5:z)  (~(dif z-in zs) zb)
  %+  expect-eq
    !>([%.y %.y %.y %.y %.y 10.208 16])
  !>  :*  ~(apt h-in h-dif)
          ~(apt h-in h-dif-rev)
          =((hz-silt h-dif) z-dif)
          =((hz-silt h-dif-rev) z-dif-rev)
          =(~(wyt h-in h-dif) ~(wyt z-in z-dif))
          ~(wyt h-in h-dif)
          ~(wyt h-in h-dif-rev)
      ==
--
