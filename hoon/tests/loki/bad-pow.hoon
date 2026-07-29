/=  np  /common/nock-prover
/=  *  /common/zeke
|%
++  testing-pow-len  64
++  gen-proof
  |=  [header=noun-digest:tip5 nonce=noun-digest:tip5]
  ^-  proof
  ~&  %generating-proof
  =/  pr  (prove:np %0 header nonce testing-pow-len)
  ?-    -.pr
      %|  ~&  %loki-failed-to-generate-proof  !!
      %&  p.pr
  ==
::
::  Shortens the number of proof items
++  bad-pow-wrong-num-items
  |=  pf=proof
  ^-  proof
  pf(objects (snip objects.pf))
::
::  Modifies the bpoly len in the %terms object
++  bad-pow-terminals-length-wrong
  |=  pf=proof
  ^-  proof
  =/  term=(list proof-data)  (grab-proof-entries pf %terms)
  ?>  =(1 (lent term))
  =/  term=proof-data  (head term)
  ?>  ?=(%terms -.term)
  =.  term  term(len.p (dec len.p.term))
  (replace-proof-entry pf %terms term 1)
::
::  Shortens the bpoly dat buffer in the %terms object
++  bad-pow-len-terminals-not-match-buffer
  |=  pf=proof
  ^-  proof
  =/  term  (grab-proof-entries pf %terms)
  ?>  =(1 (lent term))
  =/  term  (head term)
  ?>  ?=(%terms -.term)
  ::
  ::  modify the %term object dat so that the
  ::  data buffer is not the same as the len field
  ::  of the terminals bpoly
  =.  term  term(dat.p (rsh 6 dat.p.term))
  (replace-proof-entry pf %terms term 1)
::
::
::  Modifies the puzzle nonce so that the product
::  of the puzzle won't match. As a result, the
::  linking check should fail.
::
++  bad-pow-fail-input-linking
  |=  pf=proof
  ^-  proof
  =/  puzzle  (grab-proof-entries pf %puzzle)
  ?>  =(1 (lent puzzle))
  =/  puzzle  (head puzzle)
  ?>  ?=(%puzzle -.puzzle)
  =.  puzzle  puzzle(nonce nonce.puzzle(- +(-:nonce.puzzle)))
  ::
  (replace-proof-entry pf %puzzle puzzle 1)
::
++  bad-pow-eval-size-wrong-relative-to-num-cols-1
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  trace-evals  (head evals)
  ?>  ?=(%evals -.trace-evals)
  ::  modify the trace-evals bpoly length
  =.  trace-evals  trace-evals(len.p (dec len.p.trace-evals))
  ::
  (replace-proof-entry pf %evals trace-evals 1)
::
++  bad-pow-eval-size-wrong-relative-to-num-cols-2
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  trace-evals  (head evals)
  ?>  ?=(%evals -.trace-evals)
  ::  shorten the trace-evals bpoly buffer
  =.  trace-evals  trace-evals(dat.p (rsh 6 dat.p.trace-evals))
  ::
  (replace-proof-entry pf %evals trace-evals 1)
::
++  bad-pow-wrong-num-composition-pieces-1
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  comp-evals  (rear evals)
  ?>  ?=(%evals -.comp-evals)
  ::  shorten the comp-evals length
  =.  comp-evals  comp-evals(len.p (dec len.p.comp-evals))
  ::
  (replace-proof-entry pf %evals comp-evals 2)
::
++  bad-pow-wrong-num-composition-pieces-2
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  comp-evals  (rear evals)
  ?>  ?=(%evals -.comp-evals)
  ::  shorten the comp-evals bpoly buffer
  =.  comp-evals  comp-evals(dat.p (rsh 6 dat.p.comp-evals))
  ::
  (replace-proof-entry pf %evals comp-evals 2)
::
::  Modifies the trace evals to check that
::  decomp eval doesn't match comp eval
++  bad-pow-decomp-not-matching-comp-1
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  trace-evals  (head evals)
  ?>  ?=(%evals -.trace-evals)
  =/  idx  2
  =.  p.trace-evals  (twiddle-fpoly p.trace-evals idx)
  (replace-proof-entry pf %evals trace-evals 1)
::
::  Modifies the comp evals to check that
::  decomp eval doesn't match comp eval
++  bad-pow-decomp-not-matching-comp-2
  |=  pf=proof
  ^-  proof
  =/  evals  (grab-proof-entries pf %evals)
  =/  comp-evals  (rear evals)
  ?>  ?=(%evals -.comp-evals)
  =/  idx  2
  =.  p.comp-evals  (twiddle-fpoly p.comp-evals idx)
  (replace-proof-entry pf %evals comp-evals 2)
::
::  Modifies the deep merkle root
++  bad-pow-fri-deep-root-changed
  |=  pf=proof
  ^-  proof
  =/  m-roots  (grab-proof-entries pf %m-root)
  ::  deep-root is m-root #4
  =/  deep-root-idx  4
  =/  deep-root=proof-data  (snag (dec deep-root-idx) m-roots)
  ?>  ?=(%m-root -.deep-root)
  =.  p.deep-root  (twiddle-digest p.deep-root)
  (replace-proof-entry pf %m-root deep-root deep-root-idx)
::
::  Modifies the leaf of one of the trace merkle proofs
++  bad-pow-merkle-proofs-do-not-verify
  |=  pf=proof
  ^-  proof
  =/  m-paths  (grab-proof-entries pf %m-pathbf)
  =/  base-path=proof-data  (head m-paths)
  ?>  ?=(%m-pathbf -.base-path)
  =.  leaf.p.base-path  (twiddle-leaf leaf.p.base-path)
  (replace-proof-entry pf %m-pathbf base-path 1)
::
::  Inserts a copy of the trace merkle path
::  into the spot where the comp merkle path is suppose to go
++  bad-pow-deep-codeword-not-eval-of-deep-poly
  |=  pf=proof
  ^-  proof
  =/  m-paths  (grab-proof-entries pf %m-pathbf)
  =/  trace-path=proof-data  (snag 0 m-paths)
  ?>  ?=(%m-pathbf -.trace-path)
  =.  pf  (replace-proof-entry pf %m-pathbf trace-path 3)
  =/  m-roots  (grab-proof-entries pf %m-root)
  =/  trace-root=proof-data  (snag 0 m-roots)
  (replace-proof-entry pf %m-root trace-root 3)
::
::  Adds 1 to the first entry of the leaf of a merk-proof
++  twiddle-leaf
  |=  leaf=bpoly
  ^-  bpoly
  =/  bpoly-leaf  (bpoly-to-list leaf)
  =/  bel  (snag 0 bpoly-leaf)
  =.  bpoly-leaf  `(list belt)`(snap bpoly-leaf 0 +(bel))
  (init-bpoly bpoly-leaf)
::
::  Adds 1 to the first entry of the digest
++  twiddle-digest
  |=  digest=noun-digest:tip5
  ?>  (based +(-:digest))
  digest(- +(-:digest))
::
++  unbase-digest
  |=  digest=noun-digest:tip5
  ^-  noun-digest:tip5
  digest(- (add p -:digest))
::
++  unbase-noun-digests
  |=  path=(list noun-digest:tip5)
  ^-  (list noun-digest:tip5)
  (turn path unbase-digest)
::
::  Adds 1 to the entry of the fpoly at `idx`
++  twiddle-fpoly
  |=  [fp=fpoly idx=@]
  ^-  fpoly
  =/  el=felt  (~(snag fop fp) idx)
  (~(stow fop fp) idx +(el))
::
::  Adds 1 to the entry of the bpoly at `idx`
++  twiddle-bpoly
  |=  [bp=bpoly idx=@]
  ^-  bpoly
  =/  el=belt  (~(snag bop bp) idx)
  (~(stow bop bp) idx +(el))
::
::  Replaces the n-th instance of `entry` in proof with `new`
++  replace-proof-entry
  |=  [pf=proof entry=term new=proof-data n=@]
  %=  pf
      objects
    =;  [updated=(list proof-data) seen=@]
      ?:  =(seen 0)
        ~|("replace-proof-entry: could not find {<entry>} in proof" !!)
      updated
    %+  roll
      (range (lent objects.pf))
    |=  [i=@ dat=_objects.pf seen=@]
    =/  cur  (snag i dat)
    ?:  =(entry -.cur)
      =.  seen  +(seen)
      ?:  =(seen n)
        [(snap dat i new) seen]
      [dat seen]
    [dat seen]
  ==
::
::  Deletes the n-th instance of `entry` in proof
++  delete-proof-entry
  |=  [pf=proof entry=term n=@]
  ^-  proof
  =|  seen=@
  =|  scrolled=(list proof-data)
  |-
  ?~  objects.pf
    ~|("delete-proof-entry: could not find {<entry>} in proof" !!)
  =/  cur  i.objects.pf
  ?:  =(entry -.cur)
    ?:  =(+(seen) n)
      pf(objects (weld (flop scrolled) t.objects.pf))
    $(objects.pf t.objects.pf, seen +(seen), scrolled [i.objects.pf scrolled])
  $(objects.pf t.objects.pf, scrolled [i.objects.pf scrolled])
::
::  Moves the proof entry `entry` to the end of the proof
++  move-proof-entry
  |=  [pf=proof entry=term n=@]
  ^-  proof
  =/  entry-object  (grab-proof-entry pf entry n)
  =.  pf  (delete-proof-entry pf entry n)
  pf(objects (snoc objects.pf entry-object))
::
::  Returns all of the objects in the proof
::  with head tag `hed`
++  grab-proof-entries
  |=  [pf=proof hed=term]
  ^-  (list proof-data)
  %+  skim
    objects.pf
  |=  dat=proof-data
  =(hed -.dat)
::
++  grab-proof-entry
  |=  [pf=proof hed=term n=@]
  ^-  proof-data
  =/  entries  (grab-proof-entries pf hed)
  (snag (dec n) entries)
--