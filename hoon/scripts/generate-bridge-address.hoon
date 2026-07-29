/=  *  /common/tx-engine
/=  zo  /common/zoon
::  Computes the bridge multisig lock-root: the lock-root of a 3-of-5
::  multisig over the five pkhs of the bridge operator set below.
::  The result is a literal hash to be pasted into the bridge constants,
::  alongside a link back to this script.  Spending bridge-owned funds
::  requires three of five signatures from the participants below.
::
::  Re-run after any change to the participant set or threshold:
::    cargo run --profile release --bin hoon -- \
::      <path-to-this-script> <path-to-hoon-search-root>
::
::  The trace prints both the 5-tuple atom representation and the
::  base58 encoding of the resulting bridge-address.
=/  pkhs=(list hash)
  :~  (from-b58:hash 'AD6Mw1QUnPUrnVpyj2gW2jT6Jd6WsuZQmPn79XpZoFEocuvV12iDkvh')
      (from-b58:hash '6KrZT5hHLY1fva9AUDeGtZu5Jznm4RDLYfjcGjuU49nWoNym5ZeX5X5')
      (from-b58:hash 'CDLzgKWAKFXYABkuQaMwbttDSTDMh3Wy2Eoq2XiArsyxn7vScNHupBb')
      (from-b58:hash '7E47xYNVEyt7jGmLsiChUHnyw88AfBvzJfXfEQkPmMo2ZWsdcPudwmV')
      (from-b58:hash '3xSyK6RQUaYzE8YDUamkpKRHALxaYo8E7eppawwE4sP35c3PASc6koq')
  ==
=/  participant-set=(z-set:zo hash)  (z-silt:zo pkhs)
::  3-of-5 multisig: a single spend-condition with one ++pkh primitive.
::  The +pkh primitive enforces m-of-n by itself, so we don't need to
::  enumerate the m-pkh combinations as separate spend-conditions.
=/  multi-lock=lock
  [%pkh [m=3 participant-set]]~
=/  bridge-address=hash  (hash:lock multi-lock)
=/  bridge-address-b58=@t  (to-b58:hash bridge-address)
~&  bridge-address+bridge-address
~&  bridge-address-b58+bridge-address-b58
~&  bridge-address-back-to-hash+(from-b58:hash bridge-address-b58)
bridge-address
