

GREEN='\033[32m'
NC='\033[0m'


make_temp_dir(){
bitcoin_data_dir="$HOME/tmp/faisal_bitcoin/"
mkdir -p "$bitcoin_data_dir"
}


create_conf_file(){

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
    echo -e "${ORANGE}Creating or loading wallets${NC}"
    echo "**************************************"

    # Check if Miner wallet exists
    if bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner -named getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner -named loadwallet wallet_name=Miner 2>/dev/null
    else
        bitcoin-cli -datadir=$bitcoin_data_dir -named createwallet wallet_name=Miner descriptors=false
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner -named loadwallet wallet_name=Miner 2>/dev/null
    fi

    # Check if Alice wallet exists
    if bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice -named getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice -named loadwallet wallet_name=Alice 2>/dev/null
    else
        bitcoin-cli -datadir=$bitcoin_data_dir -named createwallet wallet_name=Alice descriptors=false
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice -named loadwallet wallet_name=Alice 2>/dev/null
    fi

    # Check if Bob wallet exists
    if bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob -named getwalletinfo >/dev/null 2>&1; then
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob -named loadwallet wallet_name=Bob 2>/dev/null
    else
        bitcoin-cli -datadir=$bitcoin_data_dir -named createwallet wallet_name=Bob descriptors=false
        bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob -named loadwallet wallet_name=Bob 2>/dev/null
    fi

    echo "**************************************"
    echo -e "${ORANGE}Miner, Alice, and Bob wallets are ready${NC}"
    echo "**************************************"
}



generate_address(){
    # generate addresses for the three wallets
    miner_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getnewaddress legacy)
    alice_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getnewaddress legacy)
    bob_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob getnewaddress legacy)
}


fund_wallet(){
    # funding the miner wallet
    bitcoin-cli -datadir=$bitcoin_data_dir generatetoaddress 103 "$miner_address"

    # sending 50BTC from Miner to Alice
    alice_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendtoaddress "$alice_address" 50)

    # sending 50BTC from Miner to Bob
    bob_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendtoaddress "$bob_address" 50)

    # confirming the transaction
    bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 6 $miner_address
}


creating_multisig_address() {
    alice_pubkey=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getaddressinfo "$alice_address" | grep -o '"pubkey": ".*"' | cut -d'"' -f4)
    bob_pubkey=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob getaddressinfo "$bob_address" | grep -o '"pubkey": ".*"' | cut -d'"' -f4)

    multisig_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice createmultisig 2 "[\"$alice_pubkey\", \"$bob_pubkey\"]")
    multisig_address_final=$(echo "$multisig_address" | grep -o '"address": ".*"' | cut -d'"' -f4)
}


creating_psbt(){
    alice_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice listunspent | grep -o '"txid": "[^"]*' | awk -F'"' '{print $4}' | head -n 1)
    alice_vout=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice listunspent | grep -o '"vout": [^,]*' | awk '{print $2}' | head -n 1) 

    bob_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob listunspent | grep -o '"txid": "[^"]*' | awk -F'"' '{print $4}' | head -n 1)
    bob_vout=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob listunspent | grep -o '"vout": [^,]*' | awk '{print $2}' | head -n 1)


alice_change_address=$(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet="Alice" getrawchangeaddress legacy)
bob_change_address=$(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet="Bob" getrawchangeaddress legacy)


    psbt=$(bitcoin-cli -datadir=$bitcoin_data_dir -regtest createpsbt '[{"txid":"'"$alice_txid"'","vout":'"$alice_vout"'},{"txid":"'"$bob_txid"'","vout":'"$bob_vout"'}]' '[{"'"$multisig_address_final"'":20},{"'"$alice_change_address"'":39.99999},{"'"$bob_change_address"'":39.99999}]')

    alice_signed_psbt=$(bitcoin-cli -datadir=$bitcoin_data_dir -regtest -rpcwallet=Alice walletprocesspsbt $psbt | grep -o '"psbt": "[^"]*' | awk -F'"' '{print $4}')
    alice_bob_signed_psbt=$(bitcoin-cli -datadir=$bitcoin_data_dir -regtest -rpcwallet=Bob walletprocesspsbt $alice_signed_psbt | grep -o '"psbt": "[^"]*' | awk -F'"' '{print $4}')
    psbtf=$(bitcoin-cli -datadir=$bitcoin_data_dir -regtest finalizepsbt $alice_bob_signed_psbt | grep -o '"hex": "[^"]*' | awk -F'"' '{print $4}')
    psbt_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir sendrawtransaction $psbtf)

    echo -e "PSBT sent with the following TXID ..."
    echo $psbt_txid

bitcoin-cli -datadir=$bitcoin_data_dir generatetoaddress 6 "$miner_address"
}





	


add_multisig_address(){

bitcoin-cli  -datadir=$bitcoin_data_dir  -rpcwallet="Bob"  -named addmultisigaddress  nrequired=2 keys='''["'$alice_pubkey'","'$bob_pubkey'"]'''

bitcoin-cli  -datadir=$bitcoin_data_dir  -rpcwallet="Alice"  -named addmultisigaddress  nrequired=2 keys='''["'$alice_pubkey'","'$bob_pubkey'"]'''

}

create_change_address(){

aliceReturnAddress=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getnewaddress "Alice return address"  legacy)

bobReturnAddress=$(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet=Bob getnewaddress "Bob return address"  legacy)

}

create_spending_psbt(){

psbt_spend=$(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet=Bob -named createpsbt inputs='''[ { "txid": "'$psbt_txid'", "vout": 0 } ]''' outputs='''[{ "'$bobReturnAddress'": 12.99999 },{ "'$aliceReturnAddress'": 6.99999 }]''')


aliceNewPSBT=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice walletprocesspsbt $psbt_spend | grep -o '"psbt": "[^"]*' | awk -F'"' '{print $4}')

bothNewPSBT=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob walletprocesspsbt $aliceNewPSBT | grep -o '"psbt": "[^"]*' | sed 's/"psbt": "//')

newSignedPSBT=$(bitcoin-cli -datadir=$bitcoin_data_dir finalizepsbt $bothNewPSBT | grep -o '"hex": "[^"]*' | sed 's/"hex": "//')


txid_psbt_spend=$(bitcoin-cli  -datadir=$bitcoin_data_dir  -rpcwallet="Bob" -named sendrawtransaction $newSignedPSBT)

bitcoin-cli -datadir=$bitcoin_data_dir generatetoaddress 6 "$miner_address"

}



display_balance(){
alice_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getbalance)

bob_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Bob  getbalance)

echo " Alice's balance : " $alice_balance
echo " Bob's balance : " $bob_balance

echo "${GREEN}Above is Alice and Bob's updated balance.${NC}"


}


stop_bitcoind(){

bitcoin-cli -datadir=$bitcoin_data_dir stop

}

delete_temp_dir(){

rm -rf $bitcoin_data_dir

}




make_temp_dir
create_conf_file
start_bitcoind
create_wallets
generate_address
fund_wallet
creating_multisig_address
creating_psbt
display_balance
add_multisig_address
create_change_address
create_spending_psbt
display_balance
stop_bitcoind
delete_temp_dir


















