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

# Verify the signature
sha256sum --ignore-missing -c SHA256SUMS | grep -i 'OK'
gpg --verify SHA256SUMS.asc | grep 'gpg: Good signature'

# Print a message to terminal
echo "Binary signature verification successful"

# Copy the binaries to /usr/local/bin/
sudo cp bitcoin-25.0-x86_64-linux-gnu.tar.gz /usr/local/bin/
sudo tar -xzf bitcoin-25.0-x86_64-linux-gnu.tar.gz -C /usr/local/bin/

# Add dir to path
echo "export PATH=/usr/local/bin/bitcoin-25.0/bin:$PATH" >> ~/.bashrc && source ~/.bashrc

# Delete downloaded files
rm bitcoin-25.0-x86_64-linux-gnu.tar.gz && rm SHA256SUMS && rm SHA256SUMS.asc

# Initiate

# Create and populate bitcoin.conf file
mkdir ~/.bitcoin
echo "regtest=1" >> ~/.bitcoin/bitcoin.conf && echo "fallbackfee=0.0001" >> ~/.bitcoin/bitcoin.conf && echo "server=1" >> ~/.bitcoin/bitcoin.conf && echo "txindex=1" >> ~/.bitcoin/bitcoin.conf

# Start bitcoind
bitcoind -regtest -daemon
sleep 5

#Create the Miner and Trader wallets
bitcoin-cli -regtest createwallet Miner
bitcoin-cli -regtest createwallet Trader

#Generate address from the Miner wallet
bitcoin-cli -regtest loadwallet Miner
ADDRESS=$(bitcoin-cli -regtest -rpcwallet=Miner getnewaddress "Mining Reward")

#Mine new blocks to the address until the wallet balance is positive
bitcoin-cli -regtest generatetoaddress 101 ${ADDRESS}

# Print a comment describing why wallet balance for block rewards behaves that way
echo "Wallet balance for block rewards starts at zero because block rewards are not immediately spendable. They are spendable after 100 blocks from mined block."

# Print the balance of the Miner wallet
BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalances)
echo "The balance of the Miner wallet is $BALANCE."

#USAGE

# Create a receiving address labeled "Received" from Trader wallet
RECEIVE_ADDRESS=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Received")

# Send a transaction paying 20 BTC from Miner wallet to Trader's wallet
TRANSACTION_ID=$(bitcoin-cli -regtest -rpcwallet=Miner sendtoaddress $RECEIVE_ADDRESS 20)

# Fetch the unconfirmed transaction from the node's mempool and print the result
UNCONFIRMED_TRANSACTION=$(bitcoin-cli -regtest -rpcwallet=Miner getmempoolentry $TRANSACTION_ID)

# Confirm the transaction by creating 1 more block
bitcoin-cli -regtest -rpcwallet=Miner generatetoaddress 1 $ADDRESS

# Fetch the following details of the transaction and print them into terminal
TXID=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.txid')
FROM=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.inputs[0].prevout.address')
AMOUNT=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.inputs[0].amount')
SEND=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.outputs[0].address')
SENT=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.outputs[0].amount')
CHANGE=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.outputs[1].address')
CHANGE_BACK=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.outputs[1].amount')
FEES=$(echo $UNCONFIRMED_TRANSACTION | jq -r '.fee')
BLOCK=$(bitcoin-cli -regtest getblockcount)
MINER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Miner getbalances)
TRADER_BALANCE=$(bitcoin-cli -regtest -rpcwallet=Trader getbalances)

echo "Transaction details:"
echo "TXID: $TXID"
echo "From, Amount: $FROM, $AMOUNT"
echo "Send, Amount: $SEND, $SENT"
echo "Change, Amount: $CHANGE, $CHANGE_BACK"
echo "Fees: $FEES"
echo "Block: $BLOCK"
echo "Miner Balance: $MINER_BALANCE"
echo "Trader Balance: $TRADER_BALANCE"

