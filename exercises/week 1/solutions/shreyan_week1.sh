#!/bin/bash

# Function to calculate the SHA-256 hash of a file
calculate_sha256() {
    sha256sum "$1" | awk '{ print $1 }'
}

# Function to verify the SHA-256 checksum of the downloaded binary
verify_checksum() {
    local provided_checksum="33930d432593e49d58a9bff4c30078823e9af5d98594d2935862788ce8a20aec"
    local downloaded_binary="$1"

    # Verify the downloaded binary's SHA-256 hash
    local calculated_checksum=$(calculate_sha256 "$downloaded_binary")

    if [ "$calculated_checksum" = "$provided_checksum" ]; then
        echo "Binary SHA-256 hash verification successful."

    else
        echo "Binary SHA-256 hash verification failed. The binary may have been tampered with."
        exit 1
    fi
}

# Function to verify signatures using GPG with the imported public keys
verify_signatures() {
    local signatures_file="$1"
    gpg --verify "$signatures_file" &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Binary signature verification successful."
    else
        echo "Signature verification failed for $signatures_file. The binary may have been tampered with."
        exit 1
    fi
}

# Function to copy binaries to /usr/local/bin.
copy_binaries()  {
    local downloaded_binary="$1"
    echo "Copying the extracted binaries to /usr/local/bin/..."
    tar -xzvf "$downloaded_binary" bitcoin-25.0/bin/
    sudo cp bitcoin-25.0/bin/* /usr/local/bin/ || exit 1
    echo "Bitcoin Core binaries copied to /usr/local/bin/"
}

# Function to check and create/load wallets
check_and_create_wallets() {
    local wallet_name=$1                                                                                                                                                                  
 # Define the database path                                                                                                                                                            
    db_path=$HOME/.bitcoin/regtest/wallets/$wallet_name                                                                                                                                       
 # Check if the directory exists                                                                                                                                                       
    if [ -d "$db_path" ]; then                                                                                                                                                            
        echo "The database path '$db_path' already exists."
        # Load the wallet                                                                                                                                                             
        bitcoin-cli loadwallet "$wallet_name"                                                                                                                                         
        echo "Wallet '$wallet_name' loaded."                                                                                                                                          
    else                                                                                                                                                                                  
        # Create the wallet                                                                                                                                                               
        bitcoin-cli -rpcwallet="$wallet_name" createwallet "$wallet_name"                                                                                                                 
        echo "Wallet '$wallet_name' created."                                                                                                                                             
    fi                                                                                                                                                                                    
}

# Main script

# Check if bitcoind is running.
if pgrep -x "bitcoind" > /dev/null; then
    # Stop bitcoind using bitcoin-cli                                                                                                                                                     
    bitcoin-cli stop                                                                                                                                                                      
    echo "Stopped Bitcoin Core. Let's start your Bitcoin journey from scratch. :)"                                                                                                        
else
    echo "Bitcoin Core is not already running."
fi

# Download Bitcoin Core binary for Linux x86-64
download_url="https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz"
downloaded_binary="bitcoin-25.0-x86_64-linux-gnu.tar.gz"

echo "Downloading Bitcoin Core binary for x86-64-linux-gnu..."
if wget "$download_url"; then
   echo "Download complete."
   verify_checksum "$downloaded_binary"
   verify_signatures ~/Downloads/SHA256SUMS.asc
   copy_binaries "$downloaded_binary"
else
   echo "Failed to download Bitcoin Core binary."
   exit 1
fi

# Set the data directory for the Bitcoin Core
bitcoin_data_dir="$HOME/.bitcoin/"

# Create the data directory if it doesn't exist
mkdir -p "$bitcoin_data_dir"

# Create and populate the bitcoin.conf file
echo "regtest=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "fallbackfee=0.0001" >> "$bitcoin_data_dir/bitcoin.conf"
echo "server=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "txindex=1" >> "$bitcoin_data_dir/bitcoin.conf"

# Start bitcoind
bitcoind -daemon

# Wait for bitcoind to start
sleep 2

# Check and Create the Miner Wallet
check_and_create_wallets "Miner"
# Check and Create the Trader Wallet
check_and_create_wallets "Trader"

# Generate an address for Miner wallet with the label “Mining Reward”
mining_reward_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")
echo "Mining Reward Address: $mining_reward_address"

# Mine Blocks
blocks_to_mine=101

echo "Generating valid blocks to give reward BTC to Miner.."
bitcoin-cli -rpcwallet=Miner generatetoaddress "$blocks_to_mine" "$mining_reward_address"

# Note on why wallet balance for block rewards behaves this way
: '
In regtest mode, the mining rewards are subject to a maturity period
and require additional block confirmations, even though mining itself
is much faster and easier than in the mainnet or testnet. This is to
ensure a more realistic testing environment for developers while
allowing for rapid testing and experimentation.
'

# Check the balance to verify it is in the immature state
bitcoin-cli -rpcwallet=Miner getwalletinfo

# Print the Miner Wallet Balance
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
echo "Miner Wallet Balance: $miner_balance BTC"

# Create a receiving address labeled "Received" from Trader wallet.
echo "Creating a receiving address for Trader.."
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received")
echo "Transaction address: $trader_address"

# Fetch the list of unspent UTXOs
utxos=$(bitcoin-cli -rpcwallet="Miner" listunspent)

# Select the first UTXO in the list with amount >= 20 BTC
amount_to_send=20
selected_utxo=$(echo "$utxos" | jq -r --argjson amount "$amount_to_send" 'map(select(.amount >= $amount)) | first')

if [ -z "$selected_utxo" ]; then
      echo "Error: No UTXO found with amount greater than or equal to $amount_to_send BTC."
      exit 1
fi

# Extract transaction ID and output index from the selected UTXO
txid=$(echo "$selected_utxo" | jq -r '.txid')
vout=$(echo "$selected_utxo" | jq -r '.vout')
utxo_amount=$(echo "$selected_utxo" | jq -r '.amount')

# Calculate the send amount and change amount
tx_fee=0.0001
send_amount=$amount_to_send
change_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Change")
change_amount=$(echo "$utxo_amount - $send_amount - $tx_fee" | bc)

if [ "$change_amount" \< 0 ]; then
    echo "Error: Not enough funds in the selected UTXO to cover the transaction and fee."
    exit 1
fi

# Create the raw transaction spending the selected UTXO
raw_tx=$(bitcoin-cli -rpcwallet="Miner" createrawtransaction "[{\"txid\":\"$txid\",\"vout\":$vout}]" "{\"$trader_address\":$amount_to_send, \"$change_address\":$change_amount}")

# Sign the raw transaction with the wallet and extract the hex.
signed_tx=$(bitcoin-cli -rpcwallet="Miner" signrawtransactionwithwallet "$raw_tx")
signed_tx_hex=$(echo "$signed_tx" | jq -r '.hex')

# Broadcast the signed transaction
broadcast_result=$(bitcoin-cli -rpcwallet="Miner" sendrawtransaction "$signed_tx_hex")

# Check if the broadcast_result is an error message
if [[ "$broadcast_result" == *"error"* ]]; then
    echo "Error: Transaction failed to be broadcasted."
    echo "Error message: $broadcast_result"
    exit 1
fi

# Extract the txid from the broadcast_result
transaction_id=$broadcast_result

echo "Transaction broadcasted. Transaction ID (txid): $transaction_id"

# Fetch the unconfirmed transaction from the node's mempool and print the result.
unconfirmed_transaction=$(bitcoin-cli -rpcwallet=Miner getmempoolentry "$transaction_id")
echo "Fetching the unconfirmed transaction from the mempool.."
echo "Unconfirmed transaction: $unconfirmed_transaction"

# Confirm the transaction by creating 1 more block.
echo "Wait for transaction to be confirmed..Transaction confirmed in block:"
bitcoin-cli -rpcwallet=Miner -generate 1

# Fetch the details of the transaction.
transaction_details_miner=$(bitcoin-cli -rpcwallet=Miner gettransaction $transaction_id)
transaction_details_trader=$(bitcoin-cli -rpcwallet=Trader gettransaction $transaction_id)
# Extracting required information from the transaction details.
from_address=$(echo "$selected_utxo" | jq -r '.address')
input_amount=$(echo "$transaction_details_miner" | jq '.details[0].amount')
send_amount=$(echo "$transaction_details_trader" | jq '.details[0].amount')
fees_amount=$(echo "$transaction_details_miner" | jq '.fee')
block_height=$(bitcoin-cli getblockcount)

# Fetch the balances of the Miner and Trader wallets after the transaction.
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
trader_balance=$(bitcoin-cli -rpcwallet=Trader getbalance)

# Printing the required information.
echo "Transaction Details:"
echo "txid: $transaction_id"
echo "<From, Amount>: $from_address, $input_amount"
echo "<Send, Amount>: $trader_address, $send_amount"
echo "<Change, Amount>: $change_address, $change_amount"
echo "Fees: $fees_amount"
echo "Block: $block_height"
echo "Miner Balance: $miner_balance"
echo "Trader Balance: $trader_balance"
echo "You just made your first Bitcoin transaction and your node is running in regtest successfully! Run 'bitcoin-cli --help' to explore and 'bitcoin-cli stop' to stop Bitcoin Core."
