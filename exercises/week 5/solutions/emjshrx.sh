#!/bin/bash

clear
echo "LBTCL Cohort Week 5 Script"
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
mineraddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner getnewaddress "Mining Reward")
aliceaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getnewaddress "Employer")

echo "Generating some blocks and funding Alice .... "
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 101 "$mineraddr" >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner sendtoaddress "$aliceaddr" 45 >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 "$mineraddr" >/dev/null
alice_balance=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getbalance)
if ! ((${alice_balance%.*} > 0))
then echo "Something went wrong. Alice balance is $alice_balance"
exit
fi
echo "Alice balance is $alice_balance"
echo "Creating relative timelocked transaction .... "
sequence=10
input_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].txid")
vout_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice listunspent | jq ".[0].vout")
lock_tx_hex=$(bitcoin-cli -datadir=/tmp/emjshrx  createrawtransaction '[{"txid":'$input_0',"vout":'$vout_0',"sequence":'$sequence'}]' '[{"'$mineraddr'":'10'},{"'$aliceaddr'":'34.999'}]')
signed_lock_tx=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice signrawtransactionwithwallet $lock_tx_hex | jq ".hex" | tr -d '"')
echo "Broadcasting Locked transaction .... "
bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $signed_lock_tx
echo "This fails because the lock time hasnt reached."
echo "Mining 10 blocks ......."
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 10 "$mineraddr" >/dev/null
echo "Transaction broadcasted with txid: $(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $signed_lock_tx)"
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 "$mineraddr" >/dev/null
echo "Alice balance is $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Alice getbalance)"
read -n 1 -s -r -p "This is the End.Press any key to continue"
clear
bitcoin-cli -datadir=/tmp/emjshrx stop
rm -rf  /tmp/emjshrx/
exit