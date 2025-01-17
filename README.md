# 🚩 /farbarter smart contracts

///////////
//////////
//////////
//////////////

D E P L O Y S R I P T S

DEPLOY SMART CONTRACT ON DEGEN:

source .env && forge script script/Deploy.s.sol --rpc-url $DEGEN_RPC_URL --private-key $PRIVATE_KEY --broadcast

VERIFY CONTRACT THROUGH DEGENSCAN:

forge verify-contract 0xbAeCa7e569eFea6e020014EAb898373407bBe826 FarBarter --chain-id 8453 --watch --constructor-args $(cast abi-encode "constructor()")
