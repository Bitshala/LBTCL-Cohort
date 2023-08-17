#!/bin/sh


BTC_VERSION="25.0"

echo "Downloading Bitcoin Core version ${BTC_VERSION}..."
mkdir ./tmp_build
cd ./tmp_build
wget -q https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/bitcoin-${BTC_VERSION}-x86_64-linux-gnu.tar.gz
wget -q https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/SHA256SUMS
wget -q https://bitcoincore.org/bin/bitcoin-core-${BTC_VERSION}/SHA256SUMS.asc

echo "Verifying Bitcoin Core..."
sha256sum --ignore-missing --check SHA256SUMS
if [ $? -ne 0 ]; then
  echo "ERROR: Checksum verification failed"
  exit 1
fi

git clone https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/*
gpg --verify SHA256SUMS.asc
if [ $? -ne 0 ]; then
  echo "ERROR: Could not verify Bitcoin Core"
  exit 1
fi


echo "Installing Bitcoin Core..."
tar -xzf bitcoin-${BTC_VERSION}-x86_64-linux-gnu.tar.gz
cp bitcoin-${BTC_VERSION}/bin/* /usr/local/bin/

rm -rf ./tmp/build


if [ ! -d ~/.bitcoin ]; then
  mkdir -p ~/.bitcoin ;
fi

cat <<EOF > ~/.bitcoin/bitcoin.conf
    regtest=1
    fallbackfee=0.0001
    server=1
    txindex=1
EOF

echo "Starting Bitcoin Node..."
bitcoind -daemon

sleep 6
echo "Fun stuff begins..."
bitcoin-cli -regtest createwallet Miner
bitcoin-cli -regtest createwallet Trader
ADDR_MINING=`bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Mining Reward"`

# Mining 101 blocks because block rewards can only be spendable after 100 blocks from mined block
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 101 ${ADDR_MINING}
FROM_AMOUNT=`bitcoin-cli -regtest -rpcwallet=Miner listunspent 1 9999 "[\"${ADDR_MINING}\"]" | jq '.[] | .amount'`

echo "Miner Wallet Balance:"
bitcoin-cli -regtest -rpcwallet=Miner getbalances

echo "Sending 20BTC to Trader wallet"
ADDR_TRADER=`bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Received"`
TXID_MINER_2_TRADER=`bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress ${ADDR_TRADER} 20`

bitcoin-cli -regtest -rpcwallet=Miner getmempoolentry ${TXID_MINER_2_TRADER}

bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 ${ADDR_MINING}

MINER_BALANCE=`bitcoin-cli -regtest -rpcwallet=Miner getbalances`
TRADER_BALANCE=`bitcoin-cli -regtest -rpcwallet=Trader getbalances`
SEND_AMOUNT=`bitcoin-cli -regtest -rpcwallet=Miner gettransaction ${TXID_MINER_2_TRADER} | jq .amount`
FEE=`bitcoin-cli -regtest -rpcwallet=Miner gettransaction ${TXID_MINER_2_TRADER} | jq .fee`
BLOCK=`bitcoin-cli -regtest -rpcwallet=Miner gettransaction ${TXID_MINER_2_TRADER} | jq .blockheight`
ADDR_CHANGE=`bitcoin-cli -regtest -rpcwallet=Miner listunspent 1 9990 | jq '.[] | select(.label !=  "Mining Reward")' | jq ' .address'`
CHANGE_AMOUNT=`bitcoin-cli -regtest -rpcwallet=Miner listunspent 1 9990 | jq '.[] | select(.label !=  "Mining Reward")' | jq ' .amount'`

echo "Transaction details"
echo "txid: ${TXID_MINER_2_TRADER}"
echo "<From, Amount>: <${ADDR_MINING}, ${FROM_AMOUNT}>"
echo "<Send, Amount>: <${ADDR_TRADER}, ${SEND_AMOUNT#-}>"
echo "<Change, Amount>: <${ADDR_CHANGE}, ${CHANGE_AMOUNT}>"
echo "Fees: ${FEE#-}"
echo "Block: ${BLOCK}"
echo "Miner Balance: ${MINER_BALANCE}"
echo "Trader Balance: ${TRADER_BALANCE}"

bitcoin-cli -regtest stop
