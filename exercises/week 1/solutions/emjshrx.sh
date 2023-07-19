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

read -p "Option : " option
case $option in 
0 )
    mkdir install
    cd install
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS
    sha256sum --ignore-missing --check SHA256SUMS
    # add a grep here to verify
    wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc
    git clone https://github.com/bitcoin-core/guix.sigs
    gpg --import guix.sigs/builder-keys/*
    gpg --verify SHA256SUMS.asc
    # add a grep here as well

    tar --extract bitcoin-25.0-x86_64-linux-gnu.tar.gz
    cp bitcoin-25.0-x86_64-linux-gnu /usr/local/bin/
    ;;
1 )
    echo "regtest=1" >> ~/.bitcoin/bitcoin.conf
    echo "fallbackfee=0.0001" >> ~/.bitcoin/bitcoin.conf
    bitcioind
    bitcoin-cli createwallet "Miner"
    bitcoin-cli createwallet "Trader"
    bitcoin-cli loadwallet Miner
    # generate address with label and save to var
    bitcoin-cli generatetoaddress 101 bcrt1qna46vgw2gavgvqxgrpss4phy7cxp8t30walvc9
    # coinbase transactions are locked for 100 blocks to accomadate reorgs in this time
    bitcoin-cli getbalance
    ;;
2 )
    bitcoin-cli loadwallet Trader
    txid=$(bitcoin-cli sendtoaddress n2eMqTT929pb1RDNuqEnxdaLau1rxy3efi 20)
    bitcoin-cli getmempoolentry $txid
    bitcoin-cli generatetoaddress 1 bcrt1qna46vgw2gavgvqxgrpss4phy7cxp8t30walvc9
    txdet = $(bitcoin-cli gettransaction $txid false true)
    echo "txid : " $txid
    echo $txdet | jq ".details[0].address"

;;
3 ) exit
    ;;
* ) 
    echo " Sorry invalid option"
esac
done