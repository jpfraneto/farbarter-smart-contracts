# 🚩 /farbarter smart contracts

///////////
//////////
//////////
//////////////

D E P L O Y S R I P T S

DEPLOY SMART CONTRACT ON DEGEN:

source .env && forge script script/Deploy.s.sol --rpc-url $DEGEN_RPC_URL --private-key $PRIVATE_KEY --broadcast

VERIFY CONTRACT THROUGH DEGENSCAN:

forge verify-contract 0xC83c51bf18c5E21a8111Bd7C967c1EcDB15b90E8 AnkySpandas --chain-id 666666666 --watch --constructor-args $(cast abi-encode "constructor()")
