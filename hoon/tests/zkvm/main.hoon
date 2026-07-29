/=  tt  /common/test
/=  z  /common/zeke
/=  verifier-tests  /tests/zkvm/verifier
/=  sp  /common/stark/prover

|=  [name=term =proof:sp]
^-  (list test-arm:tt)
=/  vrf-core  !>(~(. verifier-tests proof))
(get-prefix-arms:tt name vrf-core)


