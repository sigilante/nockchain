/=  tt  /common/test
/=  bip39  /tests/crypto/mod/bip39
/=  slip10  /tests/crypto/mod/slip10
/=  tip5  /tests/crypto/mod/tip5
/=  cheetah  /tests/crypto/mod/cheetah
|=  name=term
^-  (list test-arm:tt)
;:  weld
  (get-prefix-arms:tt name !>(slip10))
  (get-prefix-arms:tt name !>(bip39))
  (get-prefix-arms:tt name !>(tip5))
  (get-prefix-arms:tt name !>(cheetah))
==
