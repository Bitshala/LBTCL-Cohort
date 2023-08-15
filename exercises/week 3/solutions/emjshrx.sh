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
mineraddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner getnewaddress "Mining Reward")
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
xpub_internal_alice=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
xpub_external_alice=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

xpub_internal_bob=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
xpub_external_bob=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listdescriptors | jq '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*") )][0] | .desc' | grep -Po '(?<=\().*(?=\))')

external_desc="wsh(sortedmulti(2,$xpub_external_alice,$xpub_external_bob))"
internal_desc="wsh(sortedmulti(2,$xpub_internal_alice,$xpub_internal_bob))"

external_desc_sum=$(bitcoin-cli -datadir=/tmp/emjshrx getdescriptorinfo $external_desc | jq '.descriptor')
internal_desc_sum=$(bitcoin-cli -datadir=/tmp/emjshrx getdescriptorinfo $internal_desc | jq '.descriptor')

multisig_ext_desc="{\"desc\": $external_desc_sum, \"active\": true, \"internal\": false, \"timestamp\": \"now\"}"
multisig_int_desc="{\"desc\": $internal_desc_sum, \"active\": true, \"internal\": true, \"timestamp\": \"now\"}"

multisig_desc="[$multisig_ext_desc, $multisig_int_desc]"

bitcoin-cli -datadir=/tmp/emjshrx -named createwallet wallet_name="multisig_wallet" disable_private_keys=true blank=true

bitcoin-cli  -datadir=/tmp/emjshrx -rpcwallet="multisig_wallet" importdescriptors "$multisig_desc"

bitcoin-cli  -datadir=/tmp/emjshrx -rpcwallet="multisig_wallet" getwalletinfo
multiaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet="multisig_wallet" getnewaddress "Multisig")
echo "The multisig address : $multiaddr"

read -n 1 -s -r -p "Press any key to continue"
clear
echo "Funding MultiSig address ...."
input_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].txid")
input_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listunspent | jq ".[0].txid")
vout_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].vout")
vout_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob listunspent | jq ".[0].vout")
fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx createpsbt '[{"txid":'$input_0',"vout":'$vout_0'},{"txid":'$input_1',"vout":'$vout_1'}]' '[{"'$multiaddr'":'20'},{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]')
alice_fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice walletprocesspsbt $fund_multi_psbt | jq ".psbt" | tr -d '"')
alice_bob_fund_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob walletprocesspsbt $alice_fund_multi_psbt | jq ".psbt" | tr -d '"')
bitcoin-cli -datadir=/tmp/emjshrx decodepsbt $alice_bob_fund_multi_psbt
final_fund_multi_hex=$(bitcoin-cli -datadir=/tmp/emjshrx finalizepsbt $alice_bob_fund_multi_psbt | jq ".hex" | tr -d '"')
fund_multi_txid=$(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $final_fund_multi_hex 0)
echo "Multi sig funding Tx broadcasted with txid: $fund_multi_txid"
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 $mineraddr >/dev/null

read -n 1 -s -r -p "Press any key to continue"
clear

echo "Breaking MultiSig address ...."
break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet="multisig_wallet" -named walletcreatefundedpsbt outputs='[{"'$aliceaddr'":'9.999'},{"'$bobaddr'":'9.999'}]' | jq ".psbt" | tr -d '"')
alice_break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice walletprocesspsbt $break_multi_psbt | jq ".psbt" | tr -d '"')
alice_bob_break_multi_psbt=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob walletprocesspsbt $alice_break_multi_psbt | jq ".psbt" | tr -d '"')
final_break_multi_hex=$(bitcoin-cli -datadir=/tmp/emjshrx finalizepsbt $alice_bob_break_multi_psbt | jq ".hex" | tr -d '"')
break_multi_txid=$(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $final_break_multi_hex)
echo "Multi sig Breaking Tx broadcasted with txid: $break_multi_txid"
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 $mineraddr >/dev/null

echo "Alice balance : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getbalance)"
echo "Bob balance : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Bob getbalance)"
echo "They have same balances. Not sure how they would be different"

read -n 1 -s -r -p "Press any key to continue"
clear
bitcoin-cli -datadir=/tmp/emjshrx stop
rm -rf  /tmp/emjshrx/
exit