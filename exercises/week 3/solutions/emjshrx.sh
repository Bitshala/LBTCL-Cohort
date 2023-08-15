#!/bin/bash

clear
echo "LBTCL Cohort Week 3 Script"
read -n 1 -s -r -p "Press any key to continue"
clear
mkdir /tmp/emjshrx

cat <<EOF >/tmp/emjshrx/bitcoin.conf
    regtest=1
    fallbackfee=0.00001
    server=1
    txindex=1
EOF
bitcoind -daemon -datadir=/tmp/emjshrx
sleep 5
echo "Creating wallets .... "
bitcoin-cli -datadir=/tmp/emjshrx createwallet "Miner" >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx createwallet "Alice" >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx createwallet "Bob"  >/dev/null
mineraddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner getnewaddress "Mining Reward" legacy)
aliceaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getnewaddress "Alice")
bobaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob getnewaddress "Bob")

echo "Generating some blocks and sending to Alice and Bob .... "
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 102 $mineraddr >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner sendtoaddress $aliceaddr 25 >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner sendtoaddress $bobaddr 25 >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 $mineraddr >/dev/null
echo "Miner balance : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner getbalance)"
echo "Alice balance : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getbalance)"
echo "Bob balance : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob getbalance)"

echo "Creating MultiSig address ...."
alicehex=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getaddressinfo $aliceaddr | jq ".pubkey")
bobhex=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob getaddressinfo $bobaddr | jq ".pubkey")
multijson=$(bitcoin-cli -rpcwallet=Alice -datadir=/tmp/emjshrx createmultisig 2 "[$alicehex,$bobhex]")
multiaddr=$(echo $multijson | jq ".address")
echo "The multisig address : $multiaddr"

read -n 1 -s -r -p "Press any key to continue"
clear
echo "Funding MultiSig address ...."
input_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].txid")
input_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listunspent | jq ".[0].txid")
vout_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].vout")
vout_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listunspent | jq ".[0].vout")
fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx createpsbt '[{"txid":'$input_0',"vout":'$vout_0'},{"txid":'$input_1',"vout":'$vout_1'}]' '[{'$multiaddr':'20'},{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]')
alice_fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice walletprocesspsbt $fund_multi_psbt | jq ".psbt" | tr -d '"')
alice_bob_fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob walletprocesspsbt $alice_fund_multi_psbt | jq ".psbt" | tr -d '"')
bitcoin-cli -datadir=/tmp/emjshrx decodepsbt $alice_bob_fund_multi_psbt
final_fund_multi_hex=$(bitcoin-cli -datadir=/tmp/emjshrx finalizepsbt $alice_bob_fund_multi_psbt | jq ".hex" | tr -d '"')
fund_multi_txid=$(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $final_fund_multi_hex 0)
echo "Multi sig funding Tx broadcasted with txid: $fund_multi_txid"
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 $mineraddr >/dev/null

read -n 1 -s -r -p "Press any key to continue"
clear

#echo "Breaking MultiSig address ...."
#break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx createpsbt '[{"txid":"'$fund_multi_txid'","vout":0}]' '[{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]')
#alice_break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice walletprocesspsbt $break_multi_psbt | jq ".psbt" | tr -d '"')
#alice_bob_break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob walletprocesspsbt $alice_break_multi_psbt | jq ".psbt" | tr -d '"')
#final_break_multi_hex=$(bitcoin-cli -datadir=/tmp/emjshrx finalizepsbt $alice_bob_break_multi_psbt | jq ".hex" | tr -d '"')
#break_multi_txid=$(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $final_break_multi_hex)
#echo "Multi sig Breaking Tx broadcasted with txid: $break_multi_txid"

bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getbalance
bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob getbalance

read -n 1 -s -r -p "Press any key to continue"
clear
bitcoin-cli -datadir=/tmp/emjshrx stop
rm -rf  /tmp/emjshrx/
exit