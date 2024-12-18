# 🚩 yoink-contracts

Smart contracts for Yoink, an onchain capture the flag game.

## Deployments

| Network      | Address                                                                                                                         |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Base         | [`0x4bBFD120d9f352A0BEd7a014bd67913a2007a878`](https://basescan.org/address/0x4bBFD120d9f352A0BEd7a014bd67913a2007a878)         |
| Base Sepolia | [`0xe09c83d5a4e392965816b0e7d87a24a23ed9c90f`](https://sepolia.basescan.org/address/0xe09c83d5a4e392965816b0e7d87a24a23ed9c90f) |

///////////
//////////
//////////
//////////////

D E P L O Y S R I P T S

DEPLOY SMART CONTRACT ON BASE:

source .env && forge script script/Deploy.s.sol --rpc-url $BASE_RPC_URL --private-key $PRIVATE_KEY --broadcast

source .env && forge script script/Deploy.s.sol --rpc-url $HAM_RPC -vvvv --chain-id 5112 --broadcast

VERIFY CONTRACT THROUGH BASESCAN:

forge verify-contract 0xBc25EA092e9BEd151FD1947eE1Cf957cfdd580ef AnkyFramesgiving --chain-id 666666666 --watch --constructor-args $(cast abi-encode "constructor()")
