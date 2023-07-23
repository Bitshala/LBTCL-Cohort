#!/bin/bash

mkdir tmp
cd tmp

wget -O bitcoin-25.0-x86_64-linux-gnu.tar.gz https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz && echo "BTC tar downloaded" || echo "BTC tar download failed"

wget -O SHA256SUMS https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS

wget -O SHA256SUMS.asc https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc

sha256sum --ignore-missing --check SHA256SUMS

cnt=$(gpg --verify SHA256SUMS.asc 2>&1 >/dev/null | grep 'gpg: Good signature' | wc -l)

[[ ${cnt} -gt 0 ]] && echo "Binary signature verification successful" || echo "Binary signature verification not successful"

bitcoin_directory="/home/$USER/.bitcoin/"

mkdir -p $bitcoin_directory

cat > $bitcoin_directory/bitcoin.conf <<ENDL
regtest=1
fallbackfee=0.0001
server=1
txindex=1
ENDL


tar -xzvf bitcoin-25.0-x86_64-linux-gnu.tar.gz
sudo cp bitcoin-25.0/bin/* /usr/local/bin

# rm -rf ../tmp

echo "Starting node: "

bitcoind -daemon

echo "Creating Wallets: "

bitcoin-cli createwallet Miner
bitcoin-cli createwallet Trader

miner_add=`bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward"`

bitcoin-cli generatetoaddress 100 ${miner_add}

echo "Miner Wallet Balance:"
bitcoin-cli -rpcwallet=Miner getbalances

receiver_add=`bitcoin-cli -rpcwallet=Trader getnewaddress "Received"`

echo "Sending BTC to Trader $receiver_add"
trxid=`bitcoin-cli -rpcwallet=Miner sendtoaddress $receiver_add 20`

bitcoin-cli getmempoolentry "$trxid"

bitcoin-cli generatetoaddress 1 ${miner_add}

miner_balance=`bitcoin-cli -rpcwallet=Miner getbalance "*" 6`
trader_balance=`bitcoin-cli -rpcwallet=Trader getbalance "*" 6`

trxdetails=`bitcoin-cli -regtest -rpcwallet=Miner gettransaction ${trxid}`

echo $trxdetails

fee=`echo $trxdetails | jq '.fee' | sed 's/-//'`
blk_height=`echo $trxdetails | jq '.blockheight'`

miner_bal=`bitcoin-cli -rpcwallet=Miner getbalances`
trader_bal=`bitcoin-cli -rpcwallet=Trader getbalances`
change_add=`bitcoin-cli -rpcwallet=Miner listunspent | jq '.[]'`

cat << ENDL
trxid: $trxid
from: $miner_add , 
send: $receiver_add ,
change: $miner_add ,
fees: $fee
Block: $blk_height
miner balance: $miner_bal
trader balance: $trader_bal

ENDL


rm -rf ../tmp
bitcoin-cli stop