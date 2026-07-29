=<
|%
++  test-rap
  =/  max  (dec (bex 320))
  =/  p  +((div max 8))
  =/  jet-num  (rap 5 (rip 5 p))
  =/  unjet-num  (rap:unjet 5 (rip:unjet 5 p))
  ~&  p+p
  ~&  jet-num+jet-num
  ~&  unjet-num+unjet-num
  [jet-num unjet-num]
--
::
::  unjetted
|%
++  unjet
  |%
  ++  rip
    |=  [a=bite b=@]
    ~&  %rip
    ^-  (list @)
    ?:  =(0 b)  ~
    [(end a b) $(b (rsh a b))]
  ::
  ++  end
    |=  [a=bite b=@]
    ~&  %end
    =/  [=bloq =step]  ?^(a a [a *step])
    (mod b (bex (mul (bex bloq) step)))
  ::
  ++  rsh
    |=  [a=bite b=@]
    ~&  %rsh
    =/  [=bloq =step]  ?^(a a [a *step])
    (div b (bex (mul (bex bloq) step)))
  ::
  ++  rap
    |=  [a=bloq b=(list @)]
    ~&  %rap
    ^-  @
    ?~  b  0
    (cat a i.b $(b t.b))
  ::
  ++  cat
    |=  [a=bloq b=@ c=@]
    ~&  %cat
    (add (lsh [a (met a b)] c) b)
  ::
  ++  lsh
    |=  [a=bite b=@]
    ~&  %lsh
    =/  [=bloq =step]  ?^(a a [a *step])
    (mul b (bex (mul (bex bloq) step)))
  --
--
