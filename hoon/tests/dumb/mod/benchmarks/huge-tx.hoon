/=  helpers  /tests/dumb/helpers
/=  txe  /common/tx-engine
/=  zoon  /common/zoon
/=  *  /common/test
|%
++  h  ~(. helpers bc-pending-integration-tests:helpers)
++  t  ~(. txe bc-pending-integration-tests:helpers)
++  bench-huge-tx
  =+  [nockchain genesis]=init-nockchain:h
  ::
  ::  add 500 blocks following genesis
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2.000 nockchain)
  ::
  ::  create huge fan-in transcation with all 500 coinbases
  =/  raw=raw-tx:t
    %-  from-inputs:v0:raw-tx:t
    %-  multi:new:v0:inputs:t
    %+  turn
      (scag 10 pages)
    |=  =page:t
    =/  coin=coinbase:t  (new:v0:coinbase:t page p:default-keys-1:h)
    ?>  ?=(^ -.coin)
    %:  simple-from-note:new:v0:input:t
        p:default-keys-2:h
        coin
        s:default-keys-1:h
    ==
  =^  effects  nockchain
    (~(heard-tx k-by:h nockchain) raw)
  ~
--
