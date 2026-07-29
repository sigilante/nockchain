::  unit tests for z-by (z-map engine)
::
::  ensures treap invariants are maintained and no bad states can occur
::  where apt:z-by check would fail
::
/=  *  /common/zoon
/=  *  /common/test
::
|%
::  helper functions for testing
++  make-test-map
  |=  pairs=(list [@ @])
  ^-  (z-map @ @)
  (~(gas z-by *(z-map @ @)) pairs)
::
++  check-apt
  |=  m=(z-map @ @)
  ^-  ?
  ~(apt z-by m)
::
++  make-large-map
  |=  n=@
  ^-  (z-map @ @)
  =|  m=(z-map @ @)
  =|  i=@
  |-
  ?:  =(i n)
    m
  =.  m  (~(put z-by m) i (mul i 2))
  $(i +(i))
::
++  make-string-map
  |=  pairs=(list [@t @])
  ^-  (z-map @t @)
  (~(gas z-by *(z-map @t @)) pairs)
::
++  check-string-apt
  |=  m=(z-map @t @)
  ^-  ?
  ~(apt z-by m)
::
::  basic operation tests
++  test-empty-map-apt
  =/  m=(z-map @ @)  *(z-map @ @)
  %+  expect-eq  !>(%.y)
  !>((check-apt m))
::
++  test-single-element-apt
  =/  m=(z-map @ @)  (~(put z-by *(z-map @ @)) 1 10)
  %+  expect-eq  !>(%.y)
  !>((check-apt m))
::
++  test-put-maintains-apt
  =/  m=(z-map @ @)  *(z-map @ @)
  =.  m  (~(put z-by m) 5 50)
  =/  apt1=?  (check-apt m)
  =.  m  (~(put z-by m) 3 30)
  =/  apt2=?  (check-apt m)
  =.  m  (~(put z-by m) 7 70)
  =/  apt3=?  (check-apt m)
  =.  m  (~(put z-by m) 1 10)
  =/  apt4=?  (check-apt m)
  =.  m  (~(put z-by m) 9 90)
  =/  apt5=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4 apt5])
::
++  test-del-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40] [5 50]])
  =/  apt1=?  (check-apt m)
  =.  m  (~(del z-by m) 3)
  =/  apt2=?  (check-apt m)
  =.  m  (~(del z-by m) 1)
  =/  apt3=?  (check-apt m)
  =.  m  (~(del z-by m) 5)
  =/  apt4=?  (check-apt m)
  =.  m  (~(del z-by m) 2)
  =/  apt5=?  (check-apt m)
  =.  m  (~(del z-by m) 4)
  =/  apt6=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4 apt5 apt6])
::
++  test-gas-maintains-apt
  =/  pairs1=(list [@ @])  ~[[1 10] [3 30] [5 50]]
  =/  pairs2=(list [@ @])  ~[[2 20] [4 40] [6 60]]
  =/  m=(z-map @ @)  *(z-map @ @)
  =.  m  (~(gas z-by m) pairs1)
  =/  apt1=?  (check-apt m)
  =.  m  (~(gas z-by m) pairs2)
  =/  apt2=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
++  test-uni-maintains-apt
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [3 30] [5 50]])
  =/  m2=(z-map @ @)  (make-test-map ~[[2 20] [4 40] [6 60]])
  =/  apt1=?  (check-apt m1)
  =/  apt2=?  (check-apt m2)
  =/  m3=(z-map @ @)  (~(uni z-by m1) m2)
  =/  apt3=?  (check-apt m3)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
++  test-int-maintains-apt
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40]])
  =/  m2=(z-map @ @)  (make-test-map ~[[2 25] [3 35] [4 45] [5 55]])
  =/  apt1=?  (check-apt m1)
  =/  apt2=?  (check-apt m2)
  =/  m3=(z-map @ @)  (~(int z-by m1) m2)
  =/  apt3=?  (check-apt m3)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
++  test-dif-maintains-apt
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40] [5 50]])
  =/  m2=(z-map @ @)  (make-test-map ~[[2 20] [4 40]])
  =/  apt1=?  (check-apt m1)
  =/  apt2=?  (check-apt m2)
  =/  m3=(z-map @ @)  (~(dif z-by m1) m2)
  =/  apt3=?  (check-apt m3)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
++  test-jab-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  apt1=?  (check-apt m)
  =.  m  (~(jab z-by m) 2 |=(v=@ (mul v 10)))
  =/  apt2=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
++  test-mar-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  apt1=?  (check-apt m)
  =.  m  (~(mar z-by m) 4 (some 40))
  =/  apt2=?  (check-apt m)
  =.  m  (~(mar z-by m) 2 ~)
  =/  apt3=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
++  test-run-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  apt1=?  (check-apt m)
  =/  m2=(z-map @ @)  (~(run z-by m) |=(v=@ (mul v 2)))
  =/  apt2=?  (check-apt m2)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
++  test-urn-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  apt1=?  (check-apt m)
  =/  m2=(z-map @ @)  (~(urn z-by m) |=([k=@ v=@] (add k v)))
  =/  apt2=?  (check-apt m2)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
::  large map tests
++  test-large-map-apt
  =/  m=(z-map @ @)  (make-large-map 100)
  %+  expect-eq  !>(%.y)
  !>((check-apt m))
::
++  test-large-map-operations-apt
  =/  m=(z-map @ @)  (make-large-map 50)
  =/  apt1=?  (check-apt m)
  ::  delete every other element
  =|  i=@
  |-
  ?:  =(i 50)
    %+  expect-eq  !>([%.y %.y])
    !>([apt1 (check-apt m)])
  ?:  =(0 (mod i 2))
    =.  m  (~(del z-by m) i)
    $(i +(i))
  $(i +(i))
::
::  edge case tests
++  test-duplicate-key-updates
  =/  m=(z-map @ @)  (~(put z-by *(z-map @ @)) 1 10)
  =/  apt1=?  (check-apt m)
  =.  m  (~(put z-by m) 1 20)
  =/  apt2=?  (check-apt m)
  =/  val=@  (~(got z-by m) 1)
  %+  expect-eq  !>([%.y %.y 20])
  !>([apt1 apt2 val])
::
++  test-delete-nonexistent-key
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20]])
  =/  apt1=?  (check-apt m)
  =.  m  (~(del z-by m) 99)
  =/  apt2=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
++  test-empty-map-operations
  =/  m=(z-map @ @)  *(z-map @ @)
  =/  apt1=?  (check-apt m)
  =.  m  (~(del z-by m) 1)
  =/  apt2=?  (check-apt m)
  =/  m2=(z-map @ @)  (~(uni z-by m) m)
  =/  apt3=?  (check-apt m2)
  =/  m3=(z-map @ @)  (~(int z-by m) m)
  =/  apt4=?  (check-apt m3)
  %+  expect-eq  !>([%.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4])
::
::  complex sequence tests
++  test-complex-sequence-1
  =/  m=(z-map @ @)  *(z-map @ @)
  =.  m  (~(put z-by m) 10 100)
  =/  apt1=?  (check-apt m)
  =.  m  (~(put z-by m) 5 50)
  =/  apt2=?  (check-apt m)
  =.  m  (~(put z-by m) 15 150)
  =/  apt3=?  (check-apt m)
  =.  m  (~(put z-by m) 3 30)
  =/  apt4=?  (check-apt m)
  =.  m  (~(put z-by m) 7 70)
  =/  apt5=?  (check-apt m)
  =.  m  (~(del z-by m) 10)
  =/  apt6=?  (check-apt m)
  =.  m  (~(del z-by m) 5)
  =/  apt7=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y %.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4 apt5 apt6 apt7])
::
++  test-complex-sequence-2
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [3 30] [5 50]])
  =/  m2=(z-map @ @)  (make-test-map ~[[2 20] [4 40] [6 60]])
  =/  apt1=?  (check-apt m1)
  =/  apt2=?  (check-apt m2)
  =/  m3=(z-map @ @)  (~(uni z-by m1) m2)
  =/  apt3=?  (check-apt m3)
  =.  m3  (~(del z-by m3) 3)
  =/  apt4=?  (check-apt m3)
  =.  m3  (~(del z-by m3) 6)
  =/  apt5=?  (check-apt m3)
  =/  m4=(z-map @ @)  (~(int z-by m3) m1)
  =/  apt6=?  (check-apt m4)
  %+  expect-eq  !>([%.y %.y %.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4 apt5 apt6])
::
::  string key tests (different ordering)
++  test-string-map-apt
  =/  pairs=(list [@t @])  ~[['a' 1] ['c' 3] ['b' 2] ['d' 4]]
  =/  m=(z-map @t @)  (make-string-map pairs)
  %+  expect-eq  !>(%.y)
  !>((check-string-apt m))
::
++  test-string-map-operations
  =/  m=(z-map @t @)  (make-string-map ~[['hello' 1] ['world' 2] ['foo' 3]])
  =/  apt1=?  (check-string-apt m)
  =.  m  (~(put z-by m) 'bar' 4)
  =/  apt2=?  (check-string-apt m)
  =.  m  (~(del z-by m) 'foo')
  =/  apt3=?  (check-string-apt m)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
::  uno operation tests
++  test-uno-maintains-apt
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  m2=(z-map @ @)  (make-test-map ~[[2 25] [3 35] [4 45]])
  =/  apt1=?  (check-apt m1)
  =/  apt2=?  (check-apt m2)
  =/  m3=(z-map @ @)  ((~(uno z-by m1) m2) |=([k=@ a=@ b=@] (add a b)))
  =/  apt3=?  (check-apt m3)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
::  bif operation tests
++  test-bif-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40] [5 50]])
  =/  apt1=?  (check-apt m)
  =/  [l=(z-map @ @) r=(z-map @ @)]  (~(bif z-by m) 3)
  =/  apt2=?  (check-apt l)
  =/  apt3=?  (check-apt r)
  %+  expect-eq  !>([%.y %.y %.y])
  !>([apt1 apt2 apt3])
::
::  rib operation tests
++  test-rib-maintains-apt
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30]])
  =/  apt1=?  (check-apt m)
  =/  [sum=@ m2=(z-map @ @)]
    %+  ~(rib z-by m)  0
    |=  [[k=@ v=@] acc=@]
    [(add acc v) [k (mul v 2)]]
  =/  apt2=?  (check-apt m2)
  %+  expect-eq  !>([%.y %.y])
  !>([apt1 apt2])
::
::  rep operation tests
++  test-rep-empty-map
  =/  m=(z-map @ @)  *(z-map @ @)
  =/  result=@
    %-  ~(rep z-by m)
    |=  [[k=@ v=@] acc=@]
    (add acc (mul k v))
  %+  expect-eq  !>(0)
  !>(result)
::
++  test-rep-sum-values
  =/  m=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40]])
  =/  sum=@
    %-  ~(rep z-by m)
    |=  [[k=@ v=@] acc=@]
    (add acc v)
  %+  expect-eq  !>(100)
  !>(sum)
::
++  test-rep-key-set
  =/  m=(z-map @ @)  (make-test-map ~[[5 50] [2 20] [8 80] [1 10]])
  =/  keys=(z-set @)
    %-  ~(rep z-by m)
    |=  [[k=@ v=@] acc=(z-set @)]
    (~(put z-in acc) k)
  =/  expected=(z-set @)  (~(gas z-in *(z-set @)) ~[5 2 8 1])
  %+  expect-eq  !>(expected)
  !>(keys)
::
::  extreme edge cases
++  test-all-same-priority
  ::  This test ensures apt works even with edge case priority distributions
  =/  m=(z-map @ @)  *(z-map @ @)
  ::  Add elements in a pattern that might stress the treap balancing
  =.  m  (~(put z-by m) 50 500)
  =/  apt1=?  (check-apt m)
  =.  m  (~(put z-by m) 25 250)
  =/  apt2=?  (check-apt m)
  =.  m  (~(put z-by m) 75 750)
  =/  apt3=?  (check-apt m)
  =.  m  (~(put z-by m) 12 120)
  =/  apt4=?  (check-apt m)
  =.  m  (~(put z-by m) 37 370)
  =/  apt5=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4 apt5])
::
++  test-sequential-insert-delete
  =/  m=(z-map @ @)  *(z-map @ @)
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
    =.  m  (~(del z-by m) (sub 19 j))
    $(j +(j))
  =.  m  (~(put z-by m) i (mul i 10))
  $(i +(i))
::
++  test-reverse-sequential-insert
  =/  m=(z-map @ @)  *(z-map @ @)
  ::  insert in descending order
  =|  i=@
  |-
  ?:  =(i 20)
    %+  expect-eq  !>(%.y)
    !>((check-apt m))
  =/  key=@  (sub 19 i)
  =.  m  (~(put z-by m) key (mul key 10))
  $(i +(i))
::
::  test that all operations preserve apt even with boundary values
++  test-boundary-values
  =/  m=(z-map @ @)  *(z-map @ @)
  =.  m  (~(put z-by m) 0 0)
  =/  apt1=?  (check-apt m)
  =.  m  (~(put z-by m) `@`(dec (bex 32)) `@`(dec (bex 32)))
  =/  apt2=?  (check-apt m)
  =.  m  (~(put z-by m) 1 1)
  =/  apt3=?  (check-apt m)
  =.  m  (~(del z-by m) 0)
  =/  apt4=?  (check-apt m)
  %+  expect-eq  !>([%.y %.y %.y %.y])
  !>([apt1 apt2 apt3 apt4])
::
::  stress test with many operations
++  test-stress-many-operations
  =/  m=(z-map @ @)  *(z-map @ @)
  ::  add 30 elements
  =|  i=@
  |-
  ?:  =(i 30)
    =/  apt1=?  (check-apt m)
    ::  delete every 3rd element
    =|  j=@
    |-
    ?:  =(j 30)
      =/  apt2=?  (check-apt m)
      ::  add them back
      =|  k=@
      |-
      ?:  =(k 30)
        %+  expect-eq  !>([%.y %.y %.y])
        !>([apt1 apt2 (check-apt m)])
      ?:  =(0 (mod k 3))
        =.  m  (~(put z-by m) k (mul k 10))
        $(k +(k))
      $(k +(k))
    ?:  =(0 (mod j 3))
      =.  m  (~(del z-by m) j)
      $(j +(j))
    $(j +(j))
  =.  m  (~(put z-by m) i (mul i 10))
  $(i +(i))
::
++  test-all-functions-comprehensive
  ::  test that every z-by function preserves apt
  =/  m1=(z-map @ @)  (make-test-map ~[[1 10] [2 20] [3 30] [4 40] [5 50]])
  =/  m2=(z-map @ @)  (make-test-map ~[[3 35] [4 45] [5 55] [6 65] [7 75]])
  ::
  ::  test all operations
  =/  apt-m1=?  (check-apt m1)
  =/  apt-m2=?  (check-apt m2)
  ::
  =/  m-put=(z-map @ @)  (~(put z-by m1) 6 60)
  =/  apt-put=?  (check-apt m-put)
  ::
  =/  m-del=(z-map @ @)  (~(del z-by m1) 3)
  =/  apt-del=?  (check-apt m-del)
  ::
  =/  m-gas=(z-map @ @)  (~(gas z-by m1) ~[[6 60] [7 70]])
  =/  apt-gas=?  (check-apt m-gas)
  ::
  =/  m-uni=(z-map @ @)  (~(uni z-by m1) m2)
  =/  apt-uni=?  (check-apt m-uni)
  ::
  =/  m-int=(z-map @ @)  (~(int z-by m1) m2)
  =/  apt-int=?  (check-apt m-int)
  ::
  =/  m-dif=(z-map @ @)  (~(dif z-by m1) m2)
  =/  apt-dif=?  (check-apt m-dif)
  ::
  =/  [l=(z-map @ @) r=(z-map @ @)]  (~(bif z-by m1) 3)
  =/  apt-bif-l=?  (check-apt l)
  =/  apt-bif-r=?  (check-apt r)
  ::
  =/  all-pass=?
    ?&  apt-m1  apt-m2  apt-put  apt-del  apt-gas
        apt-uni  apt-int  apt-dif  apt-bif-l  apt-bif-r
    ==
  %+  expect-eq  !>(%.y)
  !>(all-pass)
--