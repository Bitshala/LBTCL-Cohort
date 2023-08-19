#!/bin/bash

clear
echo "LBTCL Cohort Week 4 Script"
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
bitcoin-cli -datadir=/tmp/emjshrx createwallet "Employer" >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx createwallet "Employee" >/dev/null
mineraddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner getnewaddress "Mining Reward")
employeraddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer getnewaddress "Employer")
employeeaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee getnewaddress "Employee")
echo "Generating some blocks and funding employer .... "
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 101 "$mineraddr" >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Miner sendtoaddress "$employeraddr" 45 >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 "$mineraddr" >/dev/null
echo "Creating salary transaction .... "
input_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer listunspent | jq ".[0].txid")
vout_0=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer listunspent | jq ".[0].vout")
salary_tx_hex=$(bitcoin-cli -datadir=/tmp/emjshrx  createrawtransaction '[{"txid":'$input_0',"vout":'$vout_0'}]' '[{"'$employeeaddr'":'40'},{"'$employeraddr'":'4.999'}]' 500)
signed_salary_tx=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer signrawtransactionwithwallet $salary_tx_hex | jq ".hex" | tr -d '"')
echo "Broadcasting salary transaction .... "
bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $signed_salary_tx
echo "This fails because the lock time hasnt reached."
echo "Mining 400 blocks ......."
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 400 "$mineraddr" >/dev/null
echo "Employee paid with txid: $(bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $signed_salary_tx)"
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 "$mineraddr" >/dev/null
echo "Employer balance is : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer getbalance)"
echo "Employee balance is : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee getbalance)"
read -n 1 -s -r -p "Press any key to continue"
clear
newemployeeaddr=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee getnewaddress "Employee")
input_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee listunspent | jq ".[0].txid")
vout_1=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee listunspent | jq ".[0].vout")
data_hex="4920676F74206D792073616C6172792C204920616D2072696368" # printf '%s' "I got my salary, I am rich" | xxd -p -u
spend_tx_hex=$(bitcoin-cli -datadir=/tmp/emjshrx  createrawtransaction '[{"txid":'$input_1',"vout":'$vout_1'}]' '[{"'$newemployeeaddr'":'39.999'},{"data":"'$data_hex'"}]')
signed_spend_tx=$(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee signrawtransactionwithwallet $spend_tx_hex | jq ".hex" | tr -d '"')
bitcoin-cli -datadir=/tmp/emjshrx sendrawtransaction $signed_spend_tx >/dev/null
bitcoin-cli -datadir=/tmp/emjshrx generatetoaddress 1 "$mineraddr" >/dev/null
echo "Employer balance is : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employer getbalance)"
echo "Employee balance is : $(bitcoin-cli -datadir=/tmp/emjshrx -rpcwallet=Employee getbalance)"
read -n 1 -s -r -p "This is the End.Press any key to continue"
clear
bitcoin-cli -datadir=/tmp/emjshrx stop
rm -rf  /tmp/emjshrx/
exit