# Assuming the user has downloaded bitcoin core, verified the binaries and signature, and has reset his regtest directory.

GREEN='\033[32m'
ORANGE='\033[35m'
NC='\033[0m'

# Global variables
miner_address=""
parent_txid=""
child_txid=""
txid1=""
txid2=""

create_conf_file() {
    echo "**************************************"
	echo -e "${ORANGE}Creating bitcoin.conf file${NC}"
    echo "**************************************"
	cd /Users/$USER/Library/Application\ Support/Bitcoin

	# Create a file called bitcoin.conf
	touch bitcoin.conf

	echo "regtest=1" >> bitcoin.conf
	echo "fallbackfee=0.0001" >> bitcoin.conf
	echo "server=1" >> bitcoin.conf
	echo "txindex=1" >> bitcoin.conf
}


start_bitcoind() {
    echo "**************************************"
	echo -e "${ORANGE}Starting bitcoind${NC}"
    echo "**************************************"
	# Start bitcoind in the background
	bitcoind -daemon
	# Wait for 10 seconds
	sleep 10
	# Now you can run bitcoin-cli getinfo
	bitcoin-cli -getinfo
}

echo "**************************************"
echo -e "${ORANGE}Creating two wallets${NC}"
echo "**************************************"

create_wallets() {
    # Check if Miner wallet exists
    if bitcoin-cli -regtest -rpcwallet=Miner getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -regtest -rpcwallet=Miner loadwallet "Miner" 2>/dev/null
    else
        bitcoin-cli -regtest createwallet "Miner"
        bitcoin-cli -regtest -rpcwallet=Miner loadwallet "Miner" 2>/dev/null
    fi

    # Check if Trader wallet exists
    if bitcoin-cli -regtest -rpcwallet=Trader getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -regtest -rpcwallet=Trader loadwallet "Trader" 2>/dev/null
    else
        bitcoin-cli -regtest createwallet "Trader"
        bitcoin-cli -regtest -rpcwallet=Trader loadwallet "Trader" 2>/dev/null
    fi
    echo "**************************************"
    echo -e "${GREEN}Trader and Miner wallets are ready${NC}"
    echo "**************************************"
}

echo "**************************************"
echo -e "${GREEN}Generating blocks for Miner wallet${NC}"
echo "**************************************"

generate_miner_address_and_mine_blocks() {
    miner_address=$(bitcoin-cli -regtest -rpcwallet="Miner" getnewaddress "Mining Reward")
    bitcoin-cli -regtest -rpcwallet="Miner" generatetoaddress 101 $miner_address
    original_balance=$(bitcoin-cli -regtest -rpcwallet="Miner" getbalance)

    # Check if the balance is equal to or greater than 150 BTC
    if (( $(echo "$original_balance >= 150" | bc -l) )); then
        echo -e "${GREEN}Miner wallet funded with at least 3 block rewards worth of satoshis (Starting balance: ${original_balance} BTC).${NC}"
    else
        echo -e "${ORANGE}Miner wallet balance is less than 150 BTC (Starting balance: ${original_balance} BTC).${NC}"
    fi
}

echo "**************************************"
echo -e "${GREEN}Generating trader address${NC}"
echo "**************************************"

generate_trader_address() {
    trader_address=$(bitcoin-cli -regtest -rpcwallet=Trader getnewaddress "Received")
}

# Create and send the raw transaction
create_and_send_raw_transaction() {
    # Get the list of unspent outputs (UTXOs) for Miner wallet
    unspent_outputs=$(bitcoin-cli -regtest -rpcwallet=Miner listunspent 0)

    # Extract the txid values of the first and second UTXOs using pure Bash
    txid1=$(echo "$unspent_outputs" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 1p)
    txid2=$(echo "$unspent_outputs" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 2p)

    # Print the txid values to verify
    echo -e "${GREEN}First UTXO's txid: $txid1${NC}"
    echo -e "${GREEN}Second UTXO's txid: $txid2${NC}"

    # Create the raw transaction
    rawtx_parent=$(bitcoin-cli -regtest -rpcwallet=Miner createrawtransaction '[
        {
            "txid": "'$txid1'",
            "vout": 0
        },
        {
            "txid": "'$txid2'",
            "vout": 0
        }
    ]' '{
        "'$trader_address'": 70.0,
        "'$miner_address'": 29.99999 
    }')

    # Sign the raw transaction
    output=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$rawtx_parent")

    # Extract the signed transaction hex
    signed_rawtx_parent=$(echo "$output" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    # Send the signed transaction
    parent_txid=$(bitcoin-cli -regtest -rpcwallet=Miner sendrawtransaction "$signed_rawtx_parent")

    # Print the parent transaction ID
    echo -e "${GREEN}Parent Transaction ID: $parent_txid${NC}"
}


print_transaction_info() {
    # Get the raw transaction information
    raw_transaction=$(bitcoin-cli -regtest -rpcwallet=Miner getrawtransaction "$parent_txid" )

    # Extract input information
    input1_txid=$(echo "$raw_transaction" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}')
    input1_vout=$(echo "$raw_transaction" | grep -oE '"vout": [0-9]+' | awk '{print $2}')
    input2_txid=$(echo "$raw_transaction" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 2p)
    input2_vout=$(echo "$raw_transaction" | grep -oE '"vout": [0-9]+' | awk '{print $2}' | sed -n 2p)

    # Extract output information
    output1_script_pubkey=$(echo "$raw_transaction" | grep -oE '"scriptPubKey": "[^"]+"' | awk -F'"' '{print $4}')
    output1_amount=$(echo "$raw_transaction" | grep -oE '"value": [0-9]+.[0-9]+' | awk '{print $2}')
    output2_script_pubkey=$(echo "$raw_transaction" | grep -oE '"scriptPubKey": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 2p)
    output2_amount=$(echo "$raw_transaction" | grep -oE '"value": [0-9]+.[0-9]+' | awk '{print $2}' | sed -n 2p)

    # Extract fees and weight
    fees=$(echo "$raw_transaction" | grep -oE '"value": [0-9]+.[0-9]+' | awk '{print $2}' | sed -n 3p)
    weight=$(echo -n "$raw_transaction" | wc -c)

    # Create a JSON object
    json_object=$(cat <<EOF
{
    "Transaction Information": {
        "Input": [
            {
                "txid": "$input1_txid",
                "vout": $input1_vout
            },
            {
                "txid": "$input2_txid",
                "vout": $input2_vout
            }
        ],
        "Output": [
            {
                "script_pubkey": "$output1_script_pubkey",
                "amount": $output1_amount
            },
            {
                "script_pubkey": "$output2_script_pubkey",
                "amount": $output2_amount
            }
        ],
        "Fees": $fees,
        "Weight": $weight (weight of the tx in vbytes)
    }
}
EOF
)

    # Print the JSON object
    echo -e "${GREEN}${json_object}${NC}"
}


# Function to create, sign, and send the child transaction
create_sign_send_child_transaction() {
    # Create the raw transaction
    child_raw_tx=$(bitcoin-cli -regtest -rpcwallet=Miner createrawtransaction "[
        {
            \"txid\": \"$parent_txid\",
            \"vout\": 1
        }
    ]" "{
        \"$miner_address\": 29.99998
    }")

    # Sign the raw transaction
    output_child=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$child_raw_tx")

    # Extract the signed transaction hex
    signed_rawtx_child=$(echo "$output_child" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    # Send the signed transaction
    child_txid=$(bitcoin-cli -regtest -rpcwallet=Miner sendrawtransaction "$signed_rawtx_child")

    # Print the child transaction ID
    echo -e "${GREEN}Child Transaction ID: $child_txid${NC}"
}

child_query1=$(bitcoin-cli -regtest -rpcwallet=Miner getmempoolentry $child_txid)


bump_fee_of_parent() {
# Create the raw transaction
    rawtx_parent2=$(bitcoin-cli -regtest -rpcwallet=Miner createrawtransaction '[
        {
            "txid": "'$txid1'",
            "vout": 0
        },
        {
            "txid": "'$txid2'",
            "vout": 0
        }
    ]' '{
        "'$trader_address'": 70.0,
        "'$miner_address'": 29.99998
    }')
}

    # Sign the raw transaction
    output2=$(bitcoin-cli -regtest -rpcwallet=Miner signrawtransactionwithwallet "$rawtx_parent2")

    # Extract the signed transaction hex
    signed_rawtx_parent2=$(echo "$output" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    # Send the signed transaction
    parent_txid2=$(bitcoin-cli -regtest -rpcwallet=Miner sendrawtransaction "$signed_rawtx_parent2")

    # Print the parent transaction ID
    echo -e "${GREEN}Parent Transaction ID 2: $parent_txid2${NC}"
}

child_query2=$(bitcoin-cli -regtest -rpcminer=Miner getmempoolentry $child_txid)


start_bitcoind
create_conf_file
create_wallets
generate_miner_address_and_mine_blocks
generate_trader_address
create_and_send_raw_transaction
print_transaction_info
create_sign_send_child_transaction
bump_fee_of_parent


: '
After the fee of the parent transaction is bumped the output states that the child transaction is not in the mempool.
The reason seems to be that the parent transaction that it depended upon has now been replaced, and that invalidates the child transaction. Guys, do let me know if anyone else reached the same inference.
'




