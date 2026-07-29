/=  tt  /common/test
/=  keygen-tests  /tests/wallet/mod/keygen
/=  spend  /tests/wallet/mod/spend-v1
/=  edge-cases  /tests/wallet/mod/tx-builder-edge-cases
/=  multisig  /tests/wallet/mod/tx-builder-multisig
/=  conservation  /tests/wallet/mod/tx-builder-conservation
/=  m-to-n  /tests/wallet/mod/tx-builder-m-to-n
/=  upgrade-tests  /tests/wallet/mod/state-upgrade
|=  name=term
^-  (list test-arm:tt)
;:  weld
  (get-prefix-arms:tt name !>(keygen-tests))
  (get-prefix-arms:tt name !>(spend))
  (get-prefix-arms:tt name !>(edge-cases))
  (get-prefix-arms:tt name !>(conservation))
  (get-prefix-arms:tt name !>(m-to-n))
  (get-prefix-arms:tt name !>(multisig))
  (get-prefix-arms:tt name !>(upgrade-tests))
==
