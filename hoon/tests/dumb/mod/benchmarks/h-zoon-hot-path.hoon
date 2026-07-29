::  tests/dumb/mod/benchmarks/h-zoon-hot-path.hoon
::
::    focused z-map and h-map hot-path benchmarks for digest keys.
::
/=  *  /common/h-zoon
::
|%
++  item-count  10.240
++  read-rounds  256
++  write-rounds  64
::
++  d
  |=  [salt=@ n=@]
  ^-  noun-digest:tip5:z
  :: use actual hash output. ordinal limbs create a degenerate h-tree fixture,
  :: which measures adversarial insertion order, not consensus digest keys.
  (hash-noun-varlen:tip5:z [salt n])
::
++  expected-read-sum
  |=  [n=@ rounds=@]
  ^-  @
  (mul n rounds)
::
++  seed-keys
  |=  [salt=@ n=@]
  ^-  (list noun-digest:tip5:z)
  =/  i=@  0
  =/  keys=(list noun-digest:tip5:z)  ~
  |-
  ?:  =(i n)
    keys
  $(i +(i), keys [(d salt i) keys])
::
++  seed-z-map
  |=  keys=(list noun-digest:tip5:z)
  ^-  (z-map noun-digest:tip5:z @)
  =/  m=(z-map noun-digest:tip5:z @)  *(z-map noun-digest:tip5:z @)
  |-
  ?~  keys
    m
  $(keys t.keys, m (~(put z-by m) i.keys 1))
::
++  seed-h-map
  |=  keys=(list noun-digest:tip5:z)
  ^-  (h-map noun-digest:tip5:z @)
  =/  m=(h-map noun-digest:tip5:z @)  *(h-map noun-digest:tip5:z @)
  |-
  ?~  keys
    m
  $(keys t.keys, m (~(put h-by m) i.keys 1))
::
++  sum-z-map-once
  |=  [keys=(list noun-digest:tip5:z) m=(z-map noun-digest:tip5:z @) total=@]
  ^-  @
  |-
  ?~  keys
    total
  $(keys t.keys, total (add total (~(got z-by m) i.keys)))
::
++  sum-h-map-once
  |=  [keys=(list noun-digest:tip5:z) m=(h-map noun-digest:tip5:z @) total=@]
  ^-  @
  |-
  ?~  keys
    total
  $(keys t.keys, total (add total (~(got h-by m) i.keys)))
::
++  scan-z-map
  |=  [rounds=@ keys=(list noun-digest:tip5:z) m=(z-map noun-digest:tip5:z @)]
  ^-  @
  =/  round=@  0
  =/  total=@  0
  |-
  ?:  =(round rounds)
    total
  =/  next-total=@  (sum-z-map-once keys m total)
  $(round +(round), total next-total)
::
++  scan-h-map
  |=  [rounds=@ keys=(list noun-digest:tip5:z) m=(h-map noun-digest:tip5:z @)]
  ^-  @
  =/  round=@  0
  =/  total=@  0
  |-
  ?:  =(round rounds)
    total
  =/  next-total=@  (sum-h-map-once keys m total)
  $(round +(round), total next-total)
::
++  churn-z-map-once
  |=  [keys=(list noun-digest:tip5:z) m=(z-map noun-digest:tip5:z @)]
  ^-  (z-map noun-digest:tip5:z @)
  |-
  ?~  keys
    m
  =/  key=noun-digest:tip5:z  i.keys
  =/  value=@  (~(got z-by m) key)
  =.  m  (~(put z-by m) key +(value))
  $(keys t.keys, m m)
::
++  churn-h-map-once
  |=  [keys=(list noun-digest:tip5:z) m=(h-map noun-digest:tip5:z @)]
  ^-  (h-map noun-digest:tip5:z @)
  |-
  ?~  keys
    m
  =/  key=noun-digest:tip5:z  i.keys
  =/  value=@  (~(got h-by m) key)
  =.  m  (~(put h-by m) key +(value))
  $(keys t.keys, m m)
::
++  churn-z-map
  |=  [rounds=@ keys=(list noun-digest:tip5:z) m=(z-map noun-digest:tip5:z @)]
  ^-  (z-map noun-digest:tip5:z @)
  =/  round=@  0
  |-
  ?:  =(round rounds)
    m
  =/  next=(z-map noun-digest:tip5:z @)  (churn-z-map-once keys m)
  $(round +(round), m next)
::
++  churn-h-map
  |=  [rounds=@ keys=(list noun-digest:tip5:z) m=(h-map noun-digest:tip5:z @)]
  ^-  (h-map noun-digest:tip5:z @)
  =/  round=@  0
  |-
  ?:  =(round rounds)
    m
  =/  next=(h-map noun-digest:tip5:z @)  (churn-h-map-once keys m)
  $(round +(round), m next)
::
++  bench-h-zoon-noop
  |=  salt=@
  ~
::
++  bench-h-zoon-z-map-build
  |=  salt=@
  =/  n=@  item-count
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(z-map noun-digest:tip5:z @)  (seed-z-map keys)
  ?>  =(n ~(wyt z-by m))
  ?>  ~(apt z-by m)
  ~
::
++  bench-h-zoon-h-map-build
  |=  salt=@
  =/  n=@  item-count
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(h-map noun-digest:tip5:z @)  (seed-h-map keys)
  ?>  =(n ~(wyt h-by m))
  ?>  ~(apt h-by m)
  ~
::
++  bench-h-zoon-z-map-read
  |=  salt=@
  =/  n=@  item-count
  =/  reads=@  read-rounds
  =/  expected=@  (expected-read-sum n reads)
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(z-map noun-digest:tip5:z @)  (seed-z-map keys)
  =/  total=@  (scan-z-map reads keys m)
  ?>  =(expected total)
  ?>  =(n ~(wyt z-by m))
  ?>  ~(apt z-by m)
  ~
::
++  bench-h-zoon-h-map-read
  |=  salt=@
  =/  n=@  item-count
  =/  reads=@  read-rounds
  =/  expected=@  (expected-read-sum n reads)
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(h-map noun-digest:tip5:z @)  (seed-h-map keys)
  =/  total=@  (scan-h-map reads keys m)
  ?>  =(expected total)
  ?>  =(n ~(wyt h-by m))
  ?>  ~(apt h-by m)
  ~
::
++  bench-h-zoon-z-map-update
  |=  salt=@
  =/  n=@  item-count
  =/  writes=@  write-rounds
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(z-map noun-digest:tip5:z @)  (seed-z-map keys)
  =/  churned=(z-map noun-digest:tip5:z @)  (churn-z-map writes keys m)
  ?>  =(n ~(wyt z-by churned))
  ?>  ~(apt z-by churned)
  ~
::
++  bench-h-zoon-h-map-update
  |=  salt=@
  =/  n=@  item-count
  =/  writes=@  write-rounds
  =/  keys=(list noun-digest:tip5:z)  (seed-keys salt n)
  =/  m=(h-map noun-digest:tip5:z @)  (seed-h-map keys)
  =/  churned=(h-map noun-digest:tip5:z @)  (churn-h-map writes keys m)
  ?>  =(n ~(wyt h-by churned))
  ?>  ~(apt h-by churned)
  ~
--
