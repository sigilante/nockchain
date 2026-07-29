/=  helpers  /tests/dumb/helpers
/=  txe  /common/tx-engine
/=  zoon  /common/zoon
/=  *  /common/test
|%
++  h  ~(. helpers bc-v1-phase:helpers)
++  t  ~(. txe bc-v1-phase:helpers)
++  bc-v1-timelock
  %*  .  bc-v1-phase:helpers
    coinbase-timelock-min  2
  ==
::  v1 mempool context validation tests
++  test-v1-mempool-accept-valid
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2 nockchain)
  =/  page-v1=page:t  (snag 1 pages)
  =/  bal  ~(get-cur-balance k-by:h nockchain)
  =/  coin=nnote:t
    (get-coinbase-from-balance:v1:h page-v1 bal)
  =/  pks=(list schnorr-pubkey:t)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h)
  =/  m=@  (lent pks)
  =/  [root=hash:t sc=spend-condition:v1:t *]
    (make-coinbase-lock:v1:h m pks)
  =/  fee=coins:t  sufficient-fee
  =/  sed=seed:v1:t
    (make-seed:v1:h root (sub assets.coin fee) (hash:nnote:t coin))
  =/  seds=seeds:v1:t  (~(put z-in:zoon *seeds:v1:t) sed)
  =/  sp1=spend-1:v1:t
    %*  .  *spend-1:v1:t
      witness  *witness:v1:t
      seeds    seds
      fee  fee
    ==
  =/  sig-h=hash:t  (sig-hash:spend-1:v1:t sp1)
  =/  pk=schnorr-pubkey:t  (snag 0 pks)
  =/  wit=witness:t
    (make-pkh-witness:v1:h root sc sig-h ~[[s:default-keys-1:h pk]])
  =/  sp1=spend-1:v1:t  sp1(witness wit)
  =/  nam=nname:t  ~(name get:nnote:t coin)
  =/  sps=spends:v1:t  (~(put z-by:zoon *spends:v1:t) nam [%1 sp1])
  =/  raw=raw-tx:t  (new:raw-tx:v1:t sps)
  =/  =cause:h  [%fact %0 %heard-tx raw]
  ~&  [%v1-mempool-accept-valid-raw-tx raw]
  ~&  [%v1-mempool-accept-valid-cause cause]
  =^  effs=(list effect:h)  nockchain
    (pok:h cause nockchain)
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  %+  expect-eq
    !>([%.y %.n %.y])
  !>  :*  (~(has-excluded k-by:h nockchain) tx-id)
          (~(has-bnb-raw-tx k-by:h nockchain) tx-id)
          (~(has-raw-tx k-by:h nockchain) tx-id)
      ==
::
++  test-v1-mempool-reject-gifts-fee-mismatch
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2 nockchain)
  =/  page-v0=page:t  (snag 0 pages)
  =/  coin=coinbase:t
    (new:v0:coinbase:t page-v0 p:default-keys-1:h)
  =/  pks=(list schnorr-pubkey:t)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h)
  =/  pk=schnorr-pubkey:t  (snag 0 pks)
  =/  [root=hash:t * *]
    (make-pkh-lock:v1:h 1 ~[pk])
  =/  fee=coins:t  0
  =/  bad-gift=coins:t  (sub assets.coin 1)
  =/  sed=seed:v1:t
    (make-seed:v1:h root bad-gift (hash:nnote:t coin))
  =/  seds=seeds:v1:t  (~(put z-in:zoon *seeds:v1:t) sed)
  =/  sp0=spend-0:v1:t  (new:spend-0:v1:t seds fee)
  =/  sp0=spend-0:v1:t
    (sign:spend-0:v1:t sp0 s:default-keys-1:h)
  =/  nam=nname:t  ~(name get:nnote:t coin)
  =/  sps=spends:v1:t  (~(put z-by:zoon *spends:v1:t) nam [%0 sp0])
  =/  raw=raw-tx:v1:t  (new:raw-tx:v1:t sps)
  ~&  [%v1-mempool-reject-gifts-fee-mismatch raw]
  =^  effs=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-tx raw] nockchain)
  ?>  ?&  !(~(has-raw-tx k-by:h nockchain) id.raw)
          !(~(has-excluded k-by:h nockchain) id.raw)
      ==
  ~
::
++  test-v1-mempool-reject-pkh-missing-sigs
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2 nockchain)
  =/  page-v1=page:t  (snag 1 pages)
  =/  bal  ~(get-cur-balance k-by:h nockchain)
  =/  coin=nnote:t
    (get-coinbase-from-balance:v1:h page-v1 bal)
  =/  pks=(list schnorr-pubkey:t)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h)
  =/  m=@  (lent pks)
  =/  [root=hash:t sc=spend-condition:v1:t *]
    (make-coinbase-lock:v1:h m pks)
  =/  fee=coins:t  0
  =/  sed=seed:v1:t
    (make-seed:v1:h root (sub assets.coin fee) (hash:nnote:t coin))
  =/  seds=seeds:v1:t  (~(put z-in:zoon *seeds:v1:t) sed)
  =/  sp1=spend-1:v1:t
    %*  .  *spend-1:v1:t
      witness  *witness:v1:t
      seeds    seds
      fee  fee
    ==
  =/  wit=witness:t
    %*  .  *witness:t
      lmp  (build-lock-merkle-proof:lock:t sc 1)
      pkh  *(z-map:zoon hash:t [pk=schnorr-pubkey:t sig=schnorr-signature:t])
      hax  *(z-map:zoon hash:t *)
      tim  ~
    ==
  =/  sp1=spend-1:v1:t  sp1(witness wit)
  =/  nam=nname:t  ~(name get:nnote:t coin)
  =/  sps=spends:v1:t  (~(put z-by:zoon *spends:v1:t) nam [%1 sp1])
  =/  raw=raw-tx:v1:t  (new:raw-tx:v1:t sps)
  ~&  [%v1-mempool-reject-pkh-missing-sigs raw]
  =^  effs=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-tx raw] nockchain)
  ?>  ?&  !(~(has-raw-tx k-by:h nockchain) id.raw)
          !(~(has-excluded k-by:h nockchain) id.raw)
      ==
  ~
::
++  test-v1-mempool-reject-pkh-wrong-key
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2 nockchain)
  =/  page-v1=page:t  (snag 1 pages)
  =/  bal  ~(get-cur-balance k-by:h nockchain)
  =/  coin=nnote:t
    (get-coinbase-from-balance:v1:h page-v1 bal)
  =/  pks=(list schnorr-pubkey:t)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h)
  =/  m=@  (lent pks)
  =/  [root=hash:t sc=spend-condition:v1:t *]
    (make-coinbase-lock:v1:h m pks)
  =/  fee=coins:t  0
  =/  sed=seed:v1:t
    (make-seed:v1:h root (sub assets.coin fee) (hash:nnote:t coin))
  =/  seds=seeds:v1:t  (~(put z-in:zoon *seeds:v1:t) sed)
  =/  sp1=spend-1:v1:t
    %*  .  *spend-1:v1:t
      witness  *witness:v1:t
      seeds    seds
      fee  fee
    ==
  =/  sig-h=hash:t  (sig-hash:spend-1:v1:t sp1)
  =/  pk-wrong=schnorr-pubkey:t
    (snag 0 ~(tap z-in:zoon pubkeys.p:default-keys-2:h))
  =/  wit=witness:t
    (make-pkh-witness:v1:h root sc sig-h ~[[s:default-keys-2:h pk-wrong]])
  =/  sp1=spend-1:v1:t  sp1(witness wit)
  =/  nam=nname:t  ~(name get:nnote:t coin)
  =/  sps=spends:v1:t  (~(put z-by:zoon *spends:v1:t) nam [%1 sp1])
  =/  raw=raw-tx:v1:t  (new:raw-tx:v1:t sps)
  ~&  [%v1-mempool-reject-pkh-wrong-key raw]
  =^  effs=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-tx raw] nockchain)
  ?>  ?&  !(~(has-raw-tx k-by:h nockchain) id.raw)
          !(~(has-excluded k-by:h nockchain) id.raw)
      ==
  ~
::
++  test-v1-mempool-reject-timelock
  =+  h-tim=~(. helpers bc-v1-timelock)
  =+  t-tim=~(. txe bc-v1-timelock)
  =+  [nockchain genesis]=init-nockchain:h-tim
  =^  pages  nockchain
    (add-n-pages-integration:h-tim genesis 2 nockchain)
  =/  page-v1=page:t-tim  (snag 1 pages)
  =/  bal  ~(get-cur-balance k-by:h-tim nockchain)
  =/  coin=nnote:t-tim
    (get-coinbase-from-balance:v1:h-tim page-v1 bal)
  =/  pks=(list schnorr-pubkey:t-tim)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h-tim)
  =/  m=@  (lent pks)
  =/  [root=hash:t-tim sc=spend-condition:v1:t-tim *]
    (make-coinbase-lock:v1:h-tim m pks)
  =/  fee=coins:t-tim  0
  =/  sed=seed:v1:t-tim
    (make-seed:v1:h-tim root (sub assets.coin fee) (hash:nnote:t-tim coin))
  =/  seds=seeds:v1:t-tim  (~(put z-in:zoon *seeds:v1:t-tim) sed)
  =/  sp1=spend-1:v1:t-tim
    %*  .  *spend-1:v1:t-tim
      witness  *witness:v1:t-tim
      seeds    seds
      fee  fee
    ==
  =/  sig-h=hash:t-tim  (sig-hash:spend-1:v1:t-tim sp1)
  =/  pk=schnorr-pubkey:t-tim  (snag 0 pks)
  =/  wit=witness:t-tim
    (make-pkh-witness:v1:h-tim root sc sig-h ~[[s:default-keys-1:h-tim pk]])
  =/  sp1=spend-1:v1:t-tim  sp1(witness wit)
  =/  nam=nname:t-tim  ~(name get:nnote:t-tim coin)
  =/  sps=spends:v1:t-tim  (~(put z-by:zoon *spends:v1:t-tim) nam [%1 sp1])
  =/  raw=raw-tx:v1:t-tim  (new:raw-tx:v1:t-tim sps)
  ~&  [%v1-mempool-reject-timelock raw]
  =^  effs=(list effect:h-tim)  nockchain
    (pok:h-tim [%fact %0 %heard-tx raw] nockchain)
  ?>  ?&  !(~(has-raw-tx k-by:h-tim nockchain) id.raw)
          !(~(has-excluded k-by:h-tim nockchain) id.raw)
      ==
  ~
::
::  +test-v1-mempool-reject-oversize-tx: a transaction too large to ever fit
::  in a block must be discarded on receipt (not stored, not relayed). This
::  closes the pre-packing / block-creation asymmetry that let an oversize tx
::  reach candidate blocks that were then self-rejected as %block-too-large,
:::  wedging the chain. The spend inputs are built off-state because the
:::  oversize guard runs before balance checks.
++  test-v1-mempool-reject-oversize-tx
  =+  h-med=~(. helpers bc-max-block-size-medium-v0:helpers)
  =+  h-v0=~(. helpers bc-v0-phase:helpers)
  =+  t-med=~(. txe bc-max-block-size-medium-v0:helpers)
  =+  [nockchain genesis]=init-nockchain:h-med
  =/  pages
    (make-empty-pages:h-v0 default-genesis-page:h-v0 85)
  =/  raw=raw-tx:t
    %-  from-inputs:v0:raw-tx:t
    %-  multi:new:v0:inputs:t
    %+  turn  (scag 80 pages)
    |=  =page:t
    =/  coin=coinbase:t  (new:v0:coinbase:t page p:default-keys-1:h-med)
    ?>  ?=(^ -.coin)
    %:  simple-from-note:new:v0:input:t
        p:default-keys-2:h-med
        coin
        s:default-keys-1:h-med
    ==
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  ::  sanity: this fan-in tx genuinely cannot fit in a block under the small
  ::  size limit, so a rejection is really the size guard firing (not some
  ::  other check). +compute-size-without-txs is the per-block overhead floor.
  =/  overhead=@  (compute-size-without-txs:page:t *page:t)
  ?>  (gth (add ~(size get:raw-tx:t raw) overhead) max-block-size:t-med)
  =^  effs  nockchain
    (pok:h-med [%fact %0 %heard-tx raw] nockchain)
  %+  expect-eq
    !>(%.n)
  !>((~(has-raw-tx k-by:h-med nockchain) tx-id))
::
:::  Re-broadcast gating for duplicate txs. +heard-tx never re-adds a tx that
:::  is already in raw-txs. Local grpc duplicates are gossiped; peer-origin
:::  duplicates stay silent after %seen.
:::
:::  +setup-v1-spendable-tx: a valid v1 tx spending the coinbase of a 2-block
:::  chain, plus the kernel that chain lives in.
::  a fee a block will accept. base-fee is zero under these constants, so
::  +calculate-min-fee reduces to the flat .min-fee floor, whatever the tx
::  weighs. the accept tests below fail if this ever stops sufficing.
++  sufficient-fee  ^-(coins:t 256)
::
++  setup-v1-spendable-tx
  ^-  [_nockchain:h raw-tx:t]
  (setup-v1-tx-with-fee sufficient-fee)
::
++  setup-v1-tx-with-fee
  |=  fee=coins:t
  ^-  [_nockchain:h raw-tx:t]
  =+  [nockchain genesis]=init-nockchain:h
  =^  pages  nockchain
    (add-n-pages-integration:h genesis 2 nockchain)
  =/  page-v1=page:t  (snag 1 pages)
  =/  bal  ~(get-cur-balance k-by:h nockchain)
  =/  coin=nnote:t
    (get-coinbase-from-balance:v1:h page-v1 bal)
  =/  pks=(list schnorr-pubkey:t)
    ~(tap z-in:zoon pubkeys.p:default-keys-1:h)
  =/  m=@  (lent pks)
  =/  [root=hash:t sc=spend-condition:v1:t *]
    (make-coinbase-lock:v1:h m pks)
  =/  sed=seed:v1:t
    (make-seed:v1:h root (sub assets.coin fee) (hash:nnote:t coin))
  =/  seds=seeds:v1:t  (~(put z-in:zoon *seeds:v1:t) sed)
  =/  sp1=spend-1:v1:t
    %*  .  *spend-1:v1:t
      witness  *witness:v1:t
      seeds    seds
      fee  fee
    ==
  =/  sig-h=hash:t  (sig-hash:spend-1:v1:t sp1)
  =/  pk=schnorr-pubkey:t  (snag 0 pks)
  =/  wit=witness:t
    (make-pkh-witness:v1:h root sc sig-h ~[[s:default-keys-1:h pk]])
  =/  sp1=spend-1:v1:t  sp1(witness wit)
  =/  nam=nname:t  ~(name get:nnote:t coin)
  =/  sps=spends:v1:t  (~(put z-by:zoon *spends:v1:t) nam [%1 sp1])
  [nockchain (new:raw-tx:v1:t sps)]
::
:::  Operator re-submission over grpc (`nockchain-wallet send-tx`) of an
:::  already-held tx re-gossips immediately.
++  test-v1-mempool-grpc-resend-re-gossips
  =+  [nockchain raw]=setup-v1-spendable-tx
  =/  =cause:h  [%fact %0 %heard-tx raw]
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  ::  first submission: a new tx, so it is accepted and gossiped
  =^  effs-1=(list effect:h)  nockchain
    (pok-on-wire:h grpc-wire:h cause nockchain)
  ::  we now hold it, so the resend takes the already-seen branch
  ?>  (~(has-raw-tx k-by:h nockchain) tx-id)
  ::  resend over the same grpc wire: must gossip again
  =^  effs-2=(list effect:h)  nockchain
    (pok-on-wire:h grpc-wire:h cause nockchain)
  %+  expect-eq
    !>([%.y %.y %.y])
  !>  :*  (~(has z-in:zoon (filter-heard-tx-effects:h effs-1)) raw)
          (~(has z-in:zoon (filter-heard-tx-effects:h effs-2)) raw)
          ::  still in the mempool, and never double-added
          (~(has-raw-tx k-by:h nockchain) tx-id)
      ==
::
:::  Peer-origin duplicates do not re-gossip. This terminates gossip loops.
++  test-v1-mempool-peer-resend-does-not-re-gossip
  =+  [nockchain raw]=setup-v1-spendable-tx
  =/  =cause:h  [%fact %0 %heard-tx raw]
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  ::  first time we hear it from a peer: new tx, accepted and gossiped onward
  =^  effs-1=(list effect:h)  nockchain
    (pok-on-wire:h libp2p-gossip-wire:h cause nockchain)
  ?>  (~(has-raw-tx k-by:h nockchain) tx-id)
  ::  peer sends it again: we must stay silent
  =^  effs-2=(list effect:h)  nockchain
    (pok-on-wire:h libp2p-gossip-wire:h cause nockchain)
  %+  expect-eq
    !>([%.y %.n %.y])
  !>  :*  (~(has z-in:zoon (filter-heard-tx-effects:h effs-1)) raw)
          (~(has z-in:zoon (filter-heard-tx-effects:h effs-2)) raw)
          (~(has-raw-tx k-by:h nockchain) tx-id)
      ==

::::  Chain progress, not every timer tick, re-announces retained mempool txs.
++  test-v1-mempool-new-heaviest-regossips-retained-tx
  =+  [nockchain raw]=setup-v1-spendable-tx
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  =^  effs-1=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-tx raw] nockchain)
  ?>  (~(has-raw-tx k-by:h nockchain) tx-id)
  =^  timer-effs=(list effect:h)  nockchain
    (pok:h [%command %timer ~] nockchain)
  =/  tip=page:t  ~(tip-page k-by:h nockchain)
  =/  next=page:t  (make-empty-page:h tip)
  =^  block-effs=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-block next] nockchain)
  %+  expect-eq
    !>([%.y %.n %.y %.y])
  !>  :*  (~(has z-in:zoon (filter-heard-tx-effects:h effs-1)) raw)
          (~(has z-in:zoon (filter-heard-tx-effects:h timer-effs)) raw)
          (~(has z-in:zoon (filter-heard-tx-effects:h block-effs)) raw)
          (~(has-raw-tx k-by:h nockchain) tx-id)
      ==
::
::::  A tx admitted to the mempool must be one some block can carry.
::::
::::  +v1-to-v1 requires the fee to reach +calculate-min-fee, which is at least
::::  .min-fee.data whatever the tx weighs. +heard-tx never applies that bound,
::::  so a tx paying less is admitted, gossiped, retained, re-gossiped on every
::::  new heaviest block, and re-processed by the miner on every candidate
::::  refresh -- while no block carrying it can ever validate. Its inputs stay
::::  pinned in .spent-by, so the sender cannot replace it either.
++  test-v1-mempool-rejects-tx-no-block-can-carry
  =+  [nockchain raw]=(setup-v1-tx-with-fee 0)
  =/  tx-id=tx-id:t  ~(id get:raw-tx:t raw)
  ::  the height a block carrying this tx would be at
  =/  next-height=page-number:t  3
  =/  paid-fee=coins:t
    ?^  -.raw  0
    (roll-fees:spends:t spends.raw)
  =/  required-fee=coins:t
    ?^  -.raw  0
    (calculate-min-fee:spends:t [spends.raw next-height])
  ::  sanity: this tx really does underpay, so a rejection below is the fee
  ::  bound firing and not some other check
  ?>  (lth paid-fee required-fee)
  ::  and that no block could carry it, via the same arm consensus and the
  ::  miner both run
  =/  acc=tx-acc:t
    (new:tx-acc:t `~(get-cur-balance k-by:h nockchain) next-height)
  ?>  =([%.n %v1-insufficient-fee] (process:tx-acc:t acc raw))
  ::
  =^  effs=(list effect:h)  nockchain
    (pok:h [%fact %0 %heard-tx raw] nockchain)
  ::  not held, not gossiped, and its inputs left free for a replacement
  %+  expect-eq
    !>([%.n %.n %.n])
  !>  :*  (~(has-raw-tx k-by:h nockchain) tx-id)
          (~(has z-in:zoon (filter-heard-tx-effects:h effs)) raw)
          (~(has-excluded k-by:h nockchain) tx-id)
      ==
--
