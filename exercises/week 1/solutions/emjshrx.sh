#!/bin/bash

while :
do
clear
echo "Welcome to BTC  Companion"
echo "Choose the step to execute"
echo "0. Setup "
echo "1. Initiate "
echo "2. Usage "
echo "3. Exit "

read -n 1 -p "Option : " option
case $option in 
0 )
    mkdir install
    cd install
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS
    if sha256sum --ignore-missing --check SHA256SUMS | grep -q 'bitcoin-25.0-x86_64-linux-gnu.tar.gz: OK'; then
    echo "Binary signature verification successful"
    fi
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc
    git clone https://github.com/bitcoin-core/guix.sigs
    gpg --import guix.sigs/builder-keys/*
    gpg --verify SHA256SUMS.asc
    tar --extract -f bitcoin-25.0-x86_64-linux-gnu.tar.gz
    echo "Done"
    cp bitcoin-25.0 /usr/local/bin/
    ;;
1 )
    rm ~/.bitcoin/bitcoin.conf
    echo "regtest=1
fallbackfee=0.0001
server=1
txindex=1" >> ~/.bitcoin/bitcoin.conf
    bitcoind -daemon
    sleep 5
    bitcoin-cli createwallet "Miner"
    bitcoin-cli createwallet "Trader"
    bitcoin-cli loadwallet Miner
    mineraddr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")
    bitcoin-cli generatetoaddress 101 $mineraddr
    # coinbase transactions are locked for 100 blocks to accomadate reorgs in this time
    bitcoin-cli -rpcwallet=Miner getbalance
    ;;
2 )
    bitcoin-cli loadwallet Trader
    traderaddr=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received")
    txid=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $traderaddr 20)
    bitcoin-cli -rpcwallet=Miner getmempoolentry $txid
    bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $mineraddr
    txdet=$(bitcoin-cli -rpcwallet=Miner gettransaction $txid false true)
    echo "txid : " $txid
    echo $txdet | jq "."
    ;;

3 ) 
    bitcoin-cli stop
    exit
    ;;
* ) 
    echo "Sorry invalid option"
esac
read -n 1 -s -r -p "Press any key to continue"

done