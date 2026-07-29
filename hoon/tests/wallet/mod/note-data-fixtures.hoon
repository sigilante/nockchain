/=  t  /common/tx-engine
/=  zo  /common/zoon
=<  note-data-fixtures
|%
++  note-data-fixtures
  =/  brn=spend-condition:t
    :~  [%brn ~]
    ==
  =/  lock-single=lock:t
    brn
  =/  lock-v2=lock:t
    %-  from-list:lock:t
    :~  brn
        brn
    ==
  =/  lock-v4=lock:t
    %-  from-list:lock:t
    :~  brn
        brn
        brn
        brn
    ==
  =/  lock-v8=lock:t
    %-  from-list:lock:t
    :~  brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
    ==
  =/  lock-v16=lock:t
    %-  from-list:lock:t
    :~  brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
        brn
    ==
  =/  lock-single-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%0 lock-single]]
  =/  lock-v2-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%0 lock-v2]]
  =/  lock-v4-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%0 lock-v4]]
  =/  lock-v8-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%0 lock-v8]]
  =/  lock-v16-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%0 lock-v16]]
  =/  lock-unsupported-version-note-data=note-data:v1:t
    %-  ~(put z-by:zo *note-data:v1:t)
    [%lock [%1 lock-v2]]
  =/  bridge-deposit-note-data=note-data:v1:t
    =/  bridge-payload=*  [%0 %base [11 22 33]]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge bridge-payload]
  =/  bridge-unsupported-network-note-data=note-data:v1:t
    =/  bridge-payload=*  [%0 %other [11 22 33]]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge bridge-payload]
  =/  bridge-unsupported-version-note-data=note-data:v1:t
    =/  bridge-payload=*  [%1 %base [11 22 33]]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge bridge-payload]
  =/  bridge-deposit-large-note-data=note-data:v1:t
    =/  bridge-payload=*  [%0 %base [4.200.001 98.765.432 1.234.567.890]]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge bridge-payload]
  =/  bridge-withdrawal-note-data=note-data:v1:t
    =/  withdrawal-payload=*  [%0 ~[1 2 3 4] [1 2 3 4 5] [6 7 8 9 10] 57.600]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge-w withdrawal-payload]
  =/  bridge-withdrawal-unsupported-version-note-data=note-data:v1:t
    =/  withdrawal-payload=*  [%1 ~[1 2 3 4] [1 2 3 4 5] [6 7 8 9 10] 57.600]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge-w withdrawal-payload]
  =/  bridge-withdrawal-long-event-note-data=note-data:v1:t
    =/  withdrawal-payload=*  [%0 ~[10 20 30 40 50 60 70] [90 80 70 60 50] [15 25 35 45 55] 88.001]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%bridge-w withdrawal-payload]
  =/  wildcard-note-data=note-data:v1:t
    =/  wildcard-payload=*  [%memo "wallet tx builder fixture" 42]
    %-  ~(put z-by:zo *note-data:v1:t)
    [%memo wildcard-payload]
  =/  all-keys-note-data=note-data:v1:t
    =/  nd0=note-data:v1:t  lock-v4-note-data
    =/  nd1=note-data:v1:t  (~(uni z-by:zo nd0) bridge-deposit-note-data)
    =/  nd2=note-data:v1:t  (~(uni z-by:zo nd1) bridge-withdrawal-note-data)
    (~(uni z-by:zo nd2) wildcard-note-data)
  :~  [%all-keys all-keys-note-data]
      [%lock-single lock-single-note-data]
      [%lock-v2 lock-v2-note-data]
      [%lock-v4 lock-v4-note-data]
      [%lock-v8 lock-v8-note-data]
      [%lock-v16 lock-v16-note-data]
      [%lock-unsupported-version lock-unsupported-version-note-data]
      [%bridge-deposit bridge-deposit-note-data]
      [%bridge-unsupported-network bridge-unsupported-network-note-data]
      [%bridge-unsupported-version bridge-unsupported-version-note-data]
      [%bridge-deposit-large bridge-deposit-large-note-data]
      [%bridge-withdrawal bridge-withdrawal-note-data]
      [%bridge-withdrawal-unsupported-version bridge-withdrawal-unsupported-version-note-data]
      [%bridge-withdrawal-long-event bridge-withdrawal-long-event-note-data]
      [%wildcard wildcard-note-data]
  ==
--
