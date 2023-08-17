#!/bin/bash

# Check if bitcoind is running
if pgrep -x "bitcoind" > /dev/null; then
    echo "bitcoind is already running."
else
    echo "Starting bitcoind..."
    bitcoind -daemon
    echo "bitcoind started."
fi

# Check and create wallets if needed
if [ -d "$HOME/.bitcoin/regtest/wallets/Miner" ]; then
    echo "Wallet 'Miner' already exists."
else
    bitcoin-cli createwallet "Miner"
    echo "Wallet 'Miner' created."
fi

if [ -d "$HOME/.bitcoin/regtest/wallets/Trader" ]; then
    echo "Wallet 'Trader' already exists."
else
    bitcoin-cli createwallet "Trader"
    echo "Wallet 'Trader' created."
fi
 
# Check and fund Miner wallet if needed
miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
if (( $(bc <<< "$miner_balance >= 150") )); then
    echo "Miner wallet balance is sufficient."
else
    bitcoin-cli -rpcwallet=Miner generatetoaddress 3 $(bitcoin-cli -rpcwallet=Miner getnewaddress)
    echo "Funded Miner wallet with 3 block rewards worth of BTC."
fi

# Generate a new trader address and a change address for the Miner
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress)
change_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress)

# Get UTXOs with 50 BTC amount
utxos=$(bitcoin-cli -rpcwallet=Miner listunspent)
utxo1=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[0]')
utxo2=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[1]')

# Get UTXOs details for crafting the transaction
utxo1_txid=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[0].txid')
utxo1_vout=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[0].vout')
utxo2_vout=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[1].vout')
utxo2_txid=$(echo "$utxos" | jq -r --argjson amount 50 'map(select(.amount >= $amount)) | .[1].txid')

# Craft the raw transaction
raw_parent_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[
  {\"txid\": \"$utxo1_txid\", \"vout\": $utxo1_vout},
  {\"txid\": \"$utxo2_txid\", \"vout\": $utxo2_vout}
]" "{\"$trader_address\": 70, \"$change_address\": 29.99999}")

# Sign the raw transaction
signed_parent_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$raw_parent_tx")

echo "Generated Trader Address: $trader_address"
echo "Crafted and signed raw transaction:"
echo "$signed_parent_tx"

# Extract the hex-encoded signed transaction from SIGNED_TX using jq
signed_transaction_hex=$(echo "$signed_parent_tx" | jq -r '.hex')

# Broadcast the signed transaction using bitcoin-cli. Store the txid in a variable.
transaction_id=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction "$signed_transaction_hex")

# Fetch transaction details to construct the JSON.
trader_txid=$(bitcoin-cli -rpcwallet=Trader gettransaction "$transaction_id" | jq -r '.txid')
trader_vout=$(bitcoin-cli -rpcwallet=Trader gettransaction "$transaction_id" | jq -r '.details[0].vout')
miner_txid=$(bitcoin-cli -rpcwallet=Miner gettransaction "$transaction_id" | jq -r '.txid')
miner_vout=$(bitcoin-cli -rpcwallet=Miner gettransaction "$transaction_id" | jq -r '.details[1].vout')
miner_script_pubkey=$(bitcoin-cli -rpcwallet=Miner gettxout "$transaction_id" 1 | jq -r '.scriptPubKey')
miner_amount=$(bitcoin-cli -rpcwallet=Miner gettransaction "$transaction_id" | jq -r '.details[2].amount')
trader_script_pubkey=$(bitcoin-cli -rpcwallet=Trader gettxout "$transaction_id" 0 | jq -r '.scriptPubKey')
trader_amount=$(bitcoin-cli -rpcwallet=Trader gettransaction "$transaction_id" | jq -r '.amount')                                       
fees=$(bitcoin-cli -rpcwallet=Miner gettransaction "$transaction_id" | jq -r '.fee')
weight=$(bitcoin-cli -rpcwallet=Miner gettransaction "$transaction_id" | jq -r '.weight')

# Craft the JSON structure and print it in the terminal.
json_data=$(cat <<-END
{
  "input": [
    {
      "txid": "$trader_txid",
      "vout": "$trader_vout"
    },
    {
      "txid": "$miner_txid",
      "vout": "$miner_vout"
    }
  ],
  "output": [
    {
      "script_pubkey": "$miner_script_pubkey",
      "amount": "$miner_amount"
    },
    {
      "script_pubkey": "$trader_script_pubkey",
      "amount": "$trader_amount"
    }
  ],
  "Fees": "$fees",
  "Weight": "$weight"
}
END
)
echo "Details:"
echo "$json_data"

# Fetch Miner's new address for the Child transaction output.
miner_new_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress)

# Craft the raw Child transaction.
child_raw_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[
  {\"txid\": \"$miner_txid\", \"vout\": $miner_vout}
]" "{\"$miner_new_address\": 29.99998}")

# Sign the raw Child transaction
child_signed_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$child_raw_tx")

echo "Crafted and signed raw Child transaction:"
echo "$child_signed_tx"

# Extract the hex-encoded signed Child transaction from the output using jq
child_signed_transaction_hex=$(echo "$child_signed_tx" | jq -r '.hex')

# Broadcast the signed Child transaction using bitcoin-cli. Store the txid in a variable.
child_transaction_id=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction "$child_signed_transaction_hex")

echo "Child Transaction ID: $child_transaction_id"

# Fetch the mempool entry for the Child transaction
mempool_entry=$(bitcoin-cli getmempoolentry "$child_transaction_id")

echo "Mempool Entry for Child Transaction:"
echo "$mempool_entry"

# Create a new transaction spending the same inputs of the Parent tx but with adjusted outputs
raw_rbf_tx=$(bitcoin-cli -rpcwallet=Miner createrawtransaction "[
  {\"txid\": \"$utxo1_txid\", \"vout\": $utxo1_vout},
  {\"txid\": \"$utxo2_txid\", \"vout\": $utxo2_vout}
]" "{\"$trader_address\": 70, \"$change_address\": 29.99989}")

# Sign the new RBF transaction
signed_rbf_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet "$raw_rbf_tx")

# Extract the hex-encoded signed transaction from signed_rbfparent_tx using jq
signed_rbf_tx_hex=$(echo "$signed_rbf_tx" | jq -r '.hex')

# Broadcast the signed RBF transaction
transaction_id_rbf=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction "$signed_rbf_tx_hex")
echo "Transaction ID of RBF tx: $transaction_id_rbf"

# Fetch mempool entry for the Child transaction after RBF
mempool_entry_child_rbf=$(bitcoin-cli getmempoolentry "$child_transaction_id")

echo "Mempool Entry for Child Transaction (after RBF):"
echo "$mempool_entry_child_rbf"

echo "It seems that the original child transaction: $child_transaction_id is no longer in the mempool. 
This is why we receive the error code -5 with the message: Transaction not in mempool.
This happened because the child transaction is invalidated due to the Parent transaction it referenced for its inputs(Original Parent tx TXID: $transaction_id) was replaced by
the RBF transaction(RBF Parent tx TXID: $transaction_id_rbf)."

