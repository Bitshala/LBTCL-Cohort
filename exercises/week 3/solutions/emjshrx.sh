#!/bin/bash

clear
echo "LBTCL Cohort Week 3 Script"
read -n 1 -s -r -p "Press any key to continue"
clear
bitcoind -daemon -fallbackfee=0.0001 -regtest -maxtxfee=20
sleep 5
echo "Creating wallets .... "
bitcoin-cli -regtest createwallet "Miner"
bitcoin-cli -regtest -named createwallet "Alice" #descriptors=false
bitcoin-cli -regtest -named createwallet "Bob"   #descriptors=false
bitcoin-cli -regtest loadwallet Miner >/dev/null
bitcoin-cli -regtest loadwallet Alice >/dev/null
bitcoin-cli -regtest loadwallet Bob >/dev/null
mineraddr=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Mining Reward" legacy)
aliceaddr=$(bitcoin-cli -regtest -rpcwallet=Alice getnewaddress "Alice")
bobaddr=$(bitcoin-cli -regtest -rpcwallet=Bob getnewaddress "Bob")

echo "Generating some blocks and sending to Alice and Bob .... "
bitcoin-cli -regtest generatetoaddress 102 $mineraddr >/dev/null
input_0=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress $aliceaddr 25)
input_1=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress $bobaddr 25)
bitcoin-cli -regtest generatetoaddress 1 $mineraddr >/dev/null
bitcoin-cli -regtest -rpcwallet=Miner getbalance
bitcoin-cli -regtest -rpcwallet=Alice getbalance
bitcoin-cli -regtest -rpcwallet=Bob getbalance

echo "Creating MultiSig address ...."
alicehex=$(bitcoin-cli -regtest -rpcwallet=Alice getaddressinfo $aliceaddr | jq ".pubkey")
bobhex=$(bitcoin-cli -regtest -rpcwallet=Bob getaddressinfo $bobaddr | jq ".pubkey")
multijson=$(bitcoin-cli -rpcwallet=Alice -regtest createmultisig 2 "[$alicehex,$bobhex]")
bitcoin-cli -rpcwallet=Bob -regtest createmultisig 2 "[$alicehex,$bobhex]"
multiaddr=$(echo $multijson | jq ".address")
echo "The multisig address : $multiaddr"

read -n 1 -s -r -p "Press any key to continue"
clear
echo "Funding MultiSig address ...."
fund_multi_psbt=$(bitcoin-cli -regtest createpsbt '[{"txid":"'$input_0'","vout":0},{"txid":"'$input_1'","vout":0}]' '[{'$multiaddr':'20'},{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]')
alice_fund_multi_psbt=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt $fund_multi_psbt | jq ".psbt" | tr -d '"')
alice_bob_fund_multi_psbt=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt $alice_fund_multi_psbt | jq ".psbt" | tr -d '"')
bitcoin-cli -regtest decodepsbt $alice_bob_fund_multi_psbt
final_fund_multi_hex=$(bitcoin-cli -regtest finalizepsbt $alice_bob_fund_multi_psbt | jq ".hex" | tr -d '"')
fund_multi_txid=$(bitcoin-cli -regtest sendrawtransaction $final_fund_multi_hex 0)
echo "Multi sig funding Tx broadcasted with txid: $fund_multi_txid"
bitcoin-cli -regtest generatetoaddress 1 $mineraddr >/dev/null

read -n 1 -s -r -p "Press any key to continue"
clear

#echo "Breaking MultiSig address ...."
#break_multi_psbt=$(bitcoin-cli -regtest createpsbt '[{"txid":"'$fund_multi_txid'","vout":0}]' '[{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]')
#alice_break_multi_psbt=$(bitcoin-cli -regtest -rpcwallet=Alice walletprocesspsbt $break_multi_psbt | jq ".psbt" | tr -d '"')
#alice_bob_break_multi_psbt=$(bitcoin-cli -regtest -rpcwallet=Bob walletprocesspsbt $alice_break_multi_psbt | jq ".psbt" | tr -d '"')
#final_break_multi_hex=$(bitcoin-cli -regtest finalizepsbt $alice_bob_break_multi_psbt | jq ".hex" | tr -d '"')
#break_multi_txid=$(bitcoin-cli -regtest sendrawtransaction $final_break_multi_hex)
#echo "Multi sig Breaking Tx broadcasted with txid: $break_multi_txid"

bitcoin-cli -regtest -rpcwallet=Alice getbalance
bitcoin-cli -regtest -rpcwallet=Bob getbalance

read -n 1 -s -r -p "Press any key to continue"
clear
bitcoin-cli -regtest stop
