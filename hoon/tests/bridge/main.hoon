/=  tt  /common/test
/=  bridge  /tests/bridge/mod/bridge
/=  hold-tests  /tests/bridge/mod/hold-tests
/=  withdrawal-tests  /tests/bridge/mod/withdrawal-tests
|=  name=term
^-  (list test-arm:tt)
;:  weld
  (get-prefix-arms:tt name !>(bridge))
  (get-prefix-arms:tt name !>(hold-tests))
  (get-prefix-arms:tt name !>(withdrawal-tests))
==
