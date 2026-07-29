::  jet parity tests for zoon ordering arms
::
/=  *  /common/zoon
/=  *  /common/test
::
=<
|%
++  noun-pairs
  ^-  (list [a=* b=*])
  :~  [0 0]
      [0 1]
      [1 0]
      [7 [1 2]]
      [[1 2] 7]
      [[1 2] [1 2]]
      [[1 2] [1 3]]
      [[1 3] [1 2]]
      [[1 [2 3]] [1 [2 4]]]
      [[[1 2] 3] [[1 2] 4]]
      [[[1 2] [3 4]] [[1 2] [3 5]]]
      [[[[1 2] 3] 4] [[[1 2] 3] 5]]
  ==
::
++  test-dor-tip-atom-vs-cell-regression
  %+  expect-eq  !>([%.y %.n %.y %.n])
  !>([(dor-tip 7 [1 2]) (dor-tip [1 2] 7) (dor-tip:unjet 7 [1 2]) (dor-tip:unjet [1 2] 7)])
::
++  test-dor-tip-jet-parity
  =/  ok=?
    %+  roll  noun-pairs
    |=  [[a=* b=*] acc=?]
    &(acc =((dor-tip a b) (dor-tip:unjet a b)))
  %+  expect-eq  !>(%.y)
  !>(ok)
::
++  test-gor-tip-jet-parity
  =/  ok=?
    %+  roll  noun-pairs
    |=  [[a=* b=*] acc=?]
    &(acc =((gor-tip a b) (gor-tip:unjet a b)))
  %+  expect-eq  !>(%.y)
  !>(ok)
::
++  test-mor-tip-jet-parity
  =/  ok=?
    %+  roll  noun-pairs
    |=  [[a=* b=*] acc=?]
    &(acc =((mor-tip a b) (mor-tip:unjet a b)))
  %+  expect-eq  !>(%.y)
  !>(ok)
--
::
::  unjetted ordering arms for direct jet parity checks
|%
++  unjet
  |%
  ++  dor-tip
    |=  [a=* b=*]
    ^-  ?
    ?:  =(a b)  &
    ?.  ?=(@ a)
      ?:  ?=(@ b)  |
      ?:  =(-.a -.b)
        $(a +.a, b +.b)
      $(a -.a, b -.b)
    ?.  ?=(@ b)  &
    (lth a b)
  ::
  ++  gor-tip
    |=  [a=* b=*]
    ^-  ?
    =+  [c=(tip a) d=(tip b)]
    ?:  =(c d)
      (dor-tip a b)
    (lth-tip c d)
  ::
  ++  mor-tip
    |=  [a=* b=*]
    ^-  ?
    =+  [c=(double-tip a) d=(double-tip b)]
    ?:  =(c d)
      (dor-tip a b)
    (lth-tip c d)
  --
--
