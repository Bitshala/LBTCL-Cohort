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

# Function to check if a wallet exists, and create if not
check_and_create_wallet() {
    local wallet_name="$1"
    local wallet_exists=$(bitcoin-cli -datadir="$bitcoin_data_dir" listwallets | grep "\"$wallet_name\"" -c)

    if [ "$wallet_exists" -eq 0 ]; then
        echo "Creating wallet: $wallet_name"
        bitcoin-cli -datadir="$bitcoin_data_dir" -named createwallet "$wallet_name"
    else
        echo "Loading wallet: $wallet_name"

 bitcoin-cli -datadir="$bitcoin_data_dir" -named loadwallet "$wallet_name"
    fi
}



generate_address(){
miner_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getnewaddress )


alice_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getnewaddress )

}


fund_miner(){
echo "Mining blocks, please be patient..."
bitcoin-cli -datadir=$bitcoin_data_dir generatetoaddress 103 $miner_address
}


fund_alice(){
bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendtoaddress $alice_address 20

bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 6 $miner_address
}


get_alice_balance(){

alice_balance="$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getbalance)"
echo "Alice's balance is: $alice_balance"


}



create_timelock_transaction(){
sequence=10
unspent_outputs=$(bitcoin-cli -datadir="$bitcoin_data_dir" -rpcwallet="Alice" listunspent)

alice_utxo_txid=$(echo "$unspent_outputs" | grep -o '"txid": "[^"]*' | cut -d'"' -f4)
alice_utxo_vout=$(echo "$unspent_outputs" | grep -o '"vout": [0-9]*' | awk -F' ' '{print $2}')



	rawtxhex=$(bitcoin-cli -regtest -datadir=$bitcoin_data_dir -named  -rpcwallet=Alice createrawtransaction inputs='''[ { "txid": 
"'$alice_utxo_txid'", "vout": '$alice_utxo_vout',  "sequence":'$sequence'} ]''' outputs='''{"'$miner_address'":10, 
"'$alice_address'":9.9999}''')

signedtx=$(bitcoin-cli -regtest -datadir=$bitcoin_data_dir -named -rpcwallet=Alice signrawtransactionwithwallet $rawtxhex )      

hex_value=$(echo "$signedtx" | grep -o '"hex": "[^"]*' | awk -F'"' '{print $4}')

txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice sendrawtransaction $hex_value)
}


print_inference(){

echo "As the time-lock condition has not been met we are aunable to broadcast the transaction and get the above error."
}


create_final_timelock_transaction(){

bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 10 $miner_address

txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice sendrawtransaction $hex_value)

echo "The transaction has been successfully broadcasted with the txid : $txid "
}


report_final_balance(){

alice_final_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Alice getbalance)
  echo "Alice's final balance is $alice_final_balance "

}

stop_bitcoind(){

bitcoin-cli -datadir=$bitcoin_data_dir stop

}

delete_tmp_dir(){
cd ~
rm -rf tmp/faisal_bitcoin
}


make_temp_dir
create_conf_file
start_bitcoind
check_and_create_wallet "Miner"
check_and_create_wallet "Alice"
generate_address
fund_miner
fund_alice
get_alice_balance
create_timelock_transaction
print_inference
create_final_timelock_transaction
report_final_balance
stop_bitcoind
delete_tmp_dir
