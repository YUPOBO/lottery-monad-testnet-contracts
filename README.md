## Monad Raffle (Testnet)

This is the front-end code of Monad Raffle (Testnet) implemented using NEXT.js and ethers.

project page: [monad-raffle-test.vercel.app](https://monad-raffle-test.vercel.app)

Monad Raffle (Testnet) is a web3 lottery automatically executed periodically on monad testnet.

The probability of winning is proportional to the player's invested amount.

In monad testnet, Chainlink has not yet implemented VRF and Keepers, 

but Chainlink's CCIP can be used in monad. Therefore:

- Using VRF on Avalanche's fuji net to generate random numbers. 

- Using CCIP to send random numbers to Monad testnet (The function of selecting winner is implemented in _ccipReceive).

- Using Keepers on Avalanche's fuji net to periodically call the sned function. 

MonadRaffleReceiver contract on [explorer](https://testnet.monadexplorer.com/address/0x472ed72434B35Bd562886256B5De87E887340D25?tab=Contract).

AvalancheRaffleSender contract on [explorer](https://subnets-test.avax.network/c-chain/address/0x528508327b2fa3b5d622b7c83152f8fe5d6fa3f7).

visit [frontend github page](https://github.com/YUPOBO/monad-raffle-test).

## Deploy

please refer to script/DeployExample.s.sol