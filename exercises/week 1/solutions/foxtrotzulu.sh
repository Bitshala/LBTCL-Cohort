#!/bin/bash

# Setup

# Change to home dir
cd ~

# Download the Bitcoin Core binaries
wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz

# Download the hashes and signature
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc

# Add Core Devs public keys
git clone https://github.com/bitcoin-core/guix.sigs
gpg --import guix.sigs/builder-keys/*

# Verify hash
CHECKED=$(sha256sum --ignore-missing --check SHA256SUMS)

if [[ ( $CHECKED  == "bitcoin-25.0-x86_64-linux-gnu.tar.gz: OK" ) ]]; then
        echo "File is verified OK"
else
        echo "File didn't pass the verification"
        exit 1
fi

# Verify signatures
gpg --verify SHA256SUMS.asc

# Print a message to terminal
echo "Binary signature verification successful"

# Extract and copy the binaries to /usr/local/bin/
tar -xzf bitcoin-25.0-x86_64-linux-gnu.tar.gz

sudo cp -R bitcoin-25.0/bin /usr/local/bin

echo "Instalation successful"

# Delete downloaded files
rm bitcoin-25.0-x86_64-linux-gnu.tar.gz && rm SHA256SUMS && rm SHA256SUMS.asc

# Initiate

# Create and populate bitcoin.conf file
mkdir ~/.bitcoin
echo "regtest=1" >> ~/.bitcoin/bitcoin.conf && echo "fallbackfee=0.0001" >> ~/.bitcoin/bitcoin.conf && echo "server=1" >> ~/.bitcoin/bitcoin.conf && echo "txindex=1" >> ~/.bitcoin/bitcoin.conf

# Start bitcoind
bitcoind -daemon
sleep 5

#Create the Miner and Trader wallets
bitcoin-cli createwallet Miner
bitcoin-cli createwallet Trader

#Generate address from the Miner wallet
bitcoin-cli loadwallet Miner
ADDRESS=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")

#Mine new blocks to the address until the wallet balance is positive
bitcoin-cli generatetoaddress 101 ${ADDRESS}

# Print a comment describing why wallet balance for block rewards behaves that way
echo "Wallet balance for block rewards starts at zero because block rewards are not immediately spendable. They are spendable after 100 blocks from mined block."

# Print the balance of the Miner wallet
BALANCE=$(bitcoin-cli -rpcwallet=Miner getbalances)
echo "The balance of the Miner wallet is $BALANCE"

#USAGE

# Create a receiving address labeled "Received" from Trader wallet
RECEIVE_ADDRESS=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received")

# Send a transaction paying 20 BTC from Miner wallet to Trader's wallet
TX_ID=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $RECEIVE_ADDRESS 20)

# Fetch the unconfirmed transaction from the node's mempool and print the result
UNCONFIRMED_TRANSACTION=$(bitcoin-cli -rpcwallet=Miner getmempoolentry $TX_ID)

# Confirm the transaction by creating 1 more block
bitcoin-cli -rpcwallet=Miner generatetoaddress 1 $ADDRESS

# Fetch the following details of the transaction and print them into terminal
TXID=$(echo $TX_ID | jq -r '.txid')
FROM=$(echo $TX_ID | jq -r '.inputs[0].prevout.address')
AMOUNT=$(echo $TX_ID | jq -r '.inputs[0].amount')
SEND=$(echo $TX_ID | jq -r '.outputs[0].address')
SENT=$(echo $TX_ID | jq -r '.outputs[0].amount')
CHANGE=$(echo $TX_ID | jq -r '.outputs[1].address')
CHANGE_BACK=$(echo $TX_ID | jq -r '.outputs[1].amount')
FEES=$(echo $TX_ID | jq -r '.fee')
BLOCK=$(bitcoin-cli getblockcount)
MINER_BALANCE=$(bitcoin-cli -rpcwallet=Miner getbalances)
TRADER_BALANCE=$(bitcoin-cli -rpcwallet=Trader getbalances)

echo "Transaction details:"
echo "TXID: $TX_ID"
echo "From, Amount: $FROM, $AMOUNT"
echo "Send, Amount: $SEND, $SENT"
echo "Change, Amount: $CHANGE, $CHANGE_BACK"
echo "Fees: $FEES"
echo "Block: $BLOCK"
echo "Miner Balance: $MINER_BALANCE"
echo "Trader Balance: $TRADER_BALANCE"

