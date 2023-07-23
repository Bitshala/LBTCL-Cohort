#!/bin/bash

# Setup - Download Bitcoin Core binaries, verify signature, and copy to /usr/local/bin/

# Replace these URLs with the latest release links from Bitcoin Core website
BITCOIN_CORE_DOWNLOAD_URL="https://bitcoincore.org/bin/bitcoin-core-0.22.0/bitcoin-0.22.0-x86_64-linux-gnu.tar.gz"
BITCOIN_CORE_SIGNATURE_URL="https://bitcoincore.org/bin/bitcoin-core-0.22.0/SHA256SUMS.asc"

# Download Bitcoin Core binaries
echo "Downloading Bitcoin Core binaries..."
wget -q "$BITCOIN_CORE_DOWNLOAD_URL"

# Download signature file for verification
echo "Downloading signature file..."
wget -q "$BITCOIN_CORE_SIGNATURE_URL"

# Verify the signature
echo "Verifying signature..."
signature_file=$(basename "$BITCOIN_CORE_SIGNATURE_URL")
gpg --verify "$signature_file" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "Binary signature verification successful."
else
    echo "ERROR: Binary signature verification failed. Aborting."
    exit 1
fi

# Extract and copy the binaries
tar -xzf bitcoin-*.tar.gz
sudo cp bitcoin-*/bin/* /usr/local/bin/

# Cleanup downloaded files
rm -f bitcoin-*.tar.gz "$signature_file"

# Initiate - Start bitcoind, create wallets, generate address, and mine blocks

# Start bitcoind in the background
bitcoind &

# Wait for bitcoind to initialize
sleep 10

# Create two wallets - Miner and Trader
bitcoin-cli createwallet Miner
bitcoin-cli createwallet Trader

# Generate one address from the Miner wallet with a label "Mining Reward"
mining_reward_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")

# Mine new blocks to the "Mining Reward" address until getting a positive wallet balance
mined_blocks=0
while true; do
    balance=$(bitcoin-cli -rpcwallet=Miner getbalance 0)
    if [ $(bc <<< "$balance >= 0") -eq 1 ]; then
        break
    fi
    bitcoin-cli generatetoaddress 1 "$mining_reward_address" > /dev/null
    mined_blocks=$((mined_blocks + 1))
done

# Print the number of blocks it took to get a positive wallet balance
echo "It took $mined_blocks blocks to reach a positive wallet balance."

# Explanation for why wallet balance for block rewards behaves that way:
# In Bitcoin, the newly mined coins (block rewards) have to mature before they can be spent. This maturity period is 100 blocks,
# which means the miner needs to wait for at least 100 blocks after mining a block before they can spend the newly created coins.
# During this time, the balance remains unspendable, resulting in a seemingly stagnant wallet balance.

# Print the balance of the Miner wallet
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance 0)
echo "Balance of the Miner wallet: $miner_balance BTC"

