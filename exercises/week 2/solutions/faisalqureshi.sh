
GREEN='\033[32m'
ORANGE='\033[35m'
NC='\033[0m'


download_bitcoin_core(){

wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-apple-darwin.dmg
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS
}



verify_binary_signatures(){
VERSION="25.0"
DMG_FILE="bitcoin-${VERSION}-x86_64-apple-darwin.dmg"
CHECKSUMS_FILE="SHA256SUMS"
SIGNATURE_FILE="SHA256SUMS.asc"
gpg --keyserver keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
gpg --verify "${SIGNATURE_FILE}"

if shasum -a 256 -c "${CHECKSUMS_FILE}" 2>/dev/null | grep -q "${DMG_FILE}: OK"; then
    echo "✅ Binary signature verification successful! Happy verifying! 😃"
else
    echo "❌ Binary signature verification unsuccessful! Please check the integrity of your binary. 😞"
fi
}


bitcoin_data_dir="$HOME/tmp/faisal_bitcoin/"
mkdir -p "$bitcoin_data_dir"

create_conf(){
echo "regtest=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "fallbackfee=0.0001" >> "$bitcoin_data_dir/bitcoin.conf"
echo "server=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "txindex=1" >> "$bitcoin_data_dir/bitcoin.conf"

}


start_bitcoind(){
bitcoind -datadir=$bitcoin_data_dir -daemon
sleep 5
}



create_wallets() {
    echo "**************************************"
    echo -e "${ORANGE}Creating two wallets${NC}"
    echo "**************************************"

    # Check if Miner wallet exists
    if bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner loadwallet "Miner" 2>/dev/null
    else
        bitcoin-cli -datadir=$bitcoin_data_dir createwallet "Miner"
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner loadwallet "Miner" 2>/dev/null
    fi

    # Check if Trader wallet exists
    if bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Trader getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Trader loadwallet "Trader" 2>/dev/null
    else
        bitcoin-cli -datadir=$bitcoin_data_dir createwallet "Trader"
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Trader loadwallet "Trader" 2>/dev/null
    fi

    echo "**************************************"
    echo -e "${ORANGE}Trader and Miner wallets are ready${NC}"
    echo "**************************************"
}


generate_miner_address_and_mine_blocks() {
    echo "**************************************"
    echo -e "${ORANGE}Generating blocks for Miner wallet${NC}"
    echo "**************************************"

    miner_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet="Miner" getnewaddress "Mining Reward")
    bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet="Miner" generatetoaddress 103 $miner_address
    original_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet="Miner" getbalance)

    # Check if the balance is equal to or greater than 150 BTC
    if (( $(echo "$original_balance >= 150" | bc -l) )); then
        echo -e "${GREEN}Miner wallet funded with at least 3 block rewards worth of satoshis (Starting balance: ${original_balance} BTC).${NC}"
    else
        echo -e "${ORANGE}Miner wallet balance is less than 150 BTC (Starting balance: ${original_balance} BTC).${NC}"
    fi
}


# Function to generate trader address
generate_trader_address() {
    trader_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Trader getnewaddress "Received")
    echo -e "${ORANGE}Trader address generated.${NC}"
}



extract_unspent_outputs() {
    unspent_outputs=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner listunspent 0)

    txid1=$(echo "$unspent_outputs" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 1p)
    txid2=$(echo "$unspent_outputs" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}' | sed -n 2p)

    echo -e "${GREEN}First UTXO's txid: $txid1${NC}"
    echo -e "${GREEN}Second UTXO's txid: $txid2${NC}"
}


create_parent_tx() {
    rawtx_parent=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner createrawtransaction '[
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

    output=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner signrawtransactionwithwallet "$rawtx_parent")
    signed_rawtx_parent=$(echo "$output" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    parent_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendrawtransaction "$signed_rawtx_parent")

    echo -e "${GREEN}Parent Transaction ID: ${parent_txid}"
}



print_parent_info() {
    parent_tx_details=$(bitcoin-cli -datadir=$bitcoin_data_dir getmempoolentry "$parent_txid")
    fees=$(echo "$parent_tx_details" | grep -o '"base": [^,]*' | awk '{print $2}')
    weight=$(echo "$parent_tx_details" | grep -o '"weight": [^,]*' | awk '{print $2}')

    parent_tx_info=$(bitcoin-cli -datadir=$bitcoin_data_dir decoderawtransaction "$rawtx_parent")
    vin_start=$(echo "$parent_tx_info" | grep -n '"vin": \[' | cut -d':' -f1)
    vin_end=$(echo "$parent_tx_info" | grep -n '"vout": \[' | cut -d':' -f1)
    vin=$(echo "$parent_tx_info" | tail -n +"$vin_start" | head -n "$((vin_end - vin_start - 1))")

    # Extract the txid values from the vin array
    traders_txid=$(echo "$vin" | grep -oE '"txid": "[^"]*' | awk -F'"' 'NR==1{print $4}')
    miners_txid=$(echo "$vin" | grep -oE '"txid": "[^"]*' | awk -F'"' 'NR==2{print $4}')

    # Extract the vout values from the vin array
    vout1=$(echo "$vin" | grep -oE '"vout": [0-9]*' | awk -F': ' 'NR==1{print $2}')
    vout2=$(echo "$vin" | grep -oE '"vout": [0-9]*' | awk -F': ' 'NR==2{print $2}')

    # Extract the vout array from the parent transaction info
    vout_start=$(echo "$parent_tx_info" | grep -n '"vout": \[' | cut -d':' -f1)
    vout_end=$(echo "$parent_tx_info" | grep -n ']' | cut -d':' -f1 | sed -n '2p')
    vout=$(echo "$parent_tx_info" | tail -n +"$vout_start" | head -n "$((vout_end - vout_start + 1))")

    # Extract the "vout" array from the JSON
    vout_array=$(echo "$parent_tx_info" | sed -n '/"vout": \[/,/]/p')

    # Extract the values of the "amount" fields from the "vout" array
    traders_amount=$(echo "$vout_array" | grep -o '"value": [0-9.]*' | awk '{print $2}')
    miners_amount=$(echo "$vout_array" | grep -o '"value": [0-9.]*' | awk '{print $2}' | sed -n '2p')

    # Get scriptPubKey for trader and miner addresses
    traders_scriptpubkey=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Trader getaddressinfo "$trader_address" | grep -oE '"scriptPubKey": "[^"]*' | awk -F'"' '{print 
$4}')
    miners_scriptpubkey=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getaddressinfo "$miner_address" | grep -oE '"scriptPubKey": "[^"]*' | awk -F'"' '{print $4}')

    # Construct the JSON string with variable values
    JSON='{
        "input": [
            {
                "txid": "'"${traders_txid}"'",
                "vout": '"${vout1}"'
            },
            {
                "txid": "'"${miners_txid}"'",
                "vout": '"${vout2}"'
            }
        ],
        "output": [
            {
                "script_pubkey": "'"${miners_scriptpubkey}"'",
                "amount": '"${miners_amount}"'
            },
            {
                "script_pubkey": "'"${traders_scriptpubkey}"'",
                "amount": '"${traders_amount}"'
            }
        ],
        "Fees": '"${fees}"',
        "Weight": '"${weight}"'
    }'

    # Print the JSON
    echo "$JSON"
}




create_child_tx() {
    child_raw_tx=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner createrawtransaction "[
        {
            \"txid\": \"$parent_txid\",
            \"vout\": 1
        }
    ]" "{
        \"$miner_address\": 29.99998
    }")
    output_child=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner signrawtransactionwithwallet "$child_raw_tx")
    signed_rawtx_child=$(echo "$output_child" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    child_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendrawtransaction "$signed_rawtx_child")

    echo -e "${GREEN}Child Transaction ID: $child_txid${NC}"
}


query_child() {
    child_query1=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getmempoolentry $child_txid)
}



bump_parent_tx() {
    # Create the raw transaction
    rawtx_parent=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner createrawtransaction '[
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
        "'$miner_address'": 29.99989
    }')

    # Sign the raw transaction with the wallet
    output2=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner signrawtransactionwithwallet "$rawtx_parent")

    # Extract the signed raw transaction
    signed_rawtx_parent=$(echo "$output2" | grep -oE '"hex": "[^"]+"' | awk -F'"' '{print $4}')

    # Send the signed raw transaction and get the parent_txid
    parent_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendrawtransaction "$signed_rawtx_parent")

    echo "Parent Transaction ID after fee bump: ${parent_txid}"
}


query_child2() {
    child_query1=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getmempoolentry $child_txid)
}

stop_bitcoind(){
bitcoin-cli -datadir=$bitcoin_data_dir stop
}

delete_temp_dir(){

rm -rf $bitcoin_data_dir
}


download_bitcoin_core
verify_binary_signatures
create_conf
start_bitcoind
create_wallets
generate_miner_address_and_mine_blocks
generate_trader_address
extract_unspent_outputs
create_parent_tx
print_parent_info
create_child_tx
query_child
bump_parent_tx
query_child2
stop_bitcoind
delete_temp_dir




inference=$'\033[1;32mAfter the fee of the parent transaction is bumped, the output states that the child transaction is not in the mempool.\n\nThe reason seems to be that the parent transaction it depended upon has now been replaced, and that invalidates the child transaction. Guys, do let me know if anyone else reached the same inference.\033[0m'
echo -e "$inference"

