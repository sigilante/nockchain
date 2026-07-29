::  unit tests for z-in (z-sets)
::
/=  *  /common/zoon
/=  *  /common/test
::
|%
++  test-bif
  =/  s=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[1 2 3 4 5]
  =/  [l=(z-set @) r=(z-set)]  (~(bif z-in s) 3)
  ~&  l+~(tap z-in l)
  ~&  r+~(tap z-in r)
  %+  expect-eq  !>(%.y)
  !>((~(has z-in s) 1))
::
++  test-dif-1
  =/  s=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[1 2 3 4 5]
  =/  t=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[2 3 4 5 6]
  =/  d  (~(dif z-in s) t)
  %+  expect-eq  !>(d)
  !>((~(gas z-in *(z-set @)) ~[1]))
::
++  test-dif-2
  =/  s=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[1 2 3 4 5]
  =/  t=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[7 8 9]
  =/  d  (~(dif z-in s) t)
  %+  expect-eq  !>(~(tap z-in d))
  !>(~(tap z-in s))
::
++  test-dif-3
  =/  s=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[1 2 3 4 5]
  =/  t=(z-set @)  *(z-set @)
  =/  d  (~(dif z-in s) t)
  %+  expect-eq  !>(~(tap z-in d))
  !>(~(tap z-in s))
::
++  test-put-1
  ~&  %test-put-1
  =|  z=(z-set @)
  =/  new-z  (~(put z-in z) 1)
  %+  expect-eq  !>(new-z)
  !>((~(gas z-in *(z-set @)) ~[1]))
::
++  test-put-2
  ~&  %test-put-2
  =|  z=(z-set @)
  =/  z1  (~(put z-in z) 1)
  =/  z2  (~(put z-in z1) 2)
  =/  z3  (~(put z-in z2) 3)
  =/  z4  (~(put z-in z3) 4)
  %+  expect-eq  !>(z4)
  !>((~(gas z-in *(z-set @)) ~[1 2 3 4]))
::
++  test-put-3
  ~&  %test-put-3
  =/  s=(z-set @)
    %-  ~(gas z-in *(z-set @))
    ~[1 2 3 4 5]
  =/  s2  (~(put z-in s) 1)
  %+  expect-eq  !>(s)
  !>(s2)
::
++  check-apt
  |=  m=(z-set @)
  ^-  ?
  ~(apt z-in m)
::
++  test-sequential-insert-delete-set
  =/  m  *(z-set @)
  ::  insert in ascending order
  =|  i=@
  |-
  ?:  =(i 20)
    =/  apt1=?  (check-apt m)
    ::  delete in descending order
    =|  j=@
    |-
    ?:  =(j 20)
      %+  expect-eq  !>([%.y %.y])
      !>([apt1 (check-apt m)])
    =.  m  (~(del z-in m) (sub 19 j))
    $(j +(j))
  =.  m  (~(put z-in m) i)
  $(i +(i))
--
