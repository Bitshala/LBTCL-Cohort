
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
miner_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner getnewaddress legacy)


employee_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employee getnewaddress legacy)


employer_address=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer getnewaddress legacy)

}

fund_miner(){
echo "Mining blocks, please be patient..."
bitcoin-cli -datadir=$bitcoin_data_dir generatetoaddress 103 $miner_address
}


fund_employer(){

bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner sendtoaddress $employer_address 100
bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 6 $miner_address

}



create_raw_salary_tx() {

unspent_outputs=$(bitcoin-cli -datadir="$bitcoin_data_dir" -rpcwallet="Employer" listunspent)

employer_utxo_txid=$(echo "$unspent_outputs" | grep -o '"txid": "[^"]*' | cut -d'"' -f4)
employer_utxo_vout=$(echo "$unspent_outputs" | grep -o '"vout": [0-9]*' | awk -F' ' '{print $2}')

employer_change_addr=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer getnewaddress legacy)

salary_hex=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer -named createrawtransaction inputs='''[{"txid": "'$employer_utxo_txid'", "vout": '$employer_utxo_vout' }]''' outputs='''{"'$employee_address'": 50.0, "'$employer_change_addr'":49.99999 }''' locktime=500)   


signed_tx_output=$(bitcoin-cli -datadir="$bitcoin_data_dir" -rpcwallet="Employer" signrawtransactionwithwallet "$salary_hex") 

signed_hex=$(echo "$signed_tx_output" | awk -F'"' '/hex/{print $4}')

salary_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer sendrawtransaction $signed_hex)


}



print_inference(){
echo " I got an error stating that the transaction is 'non-final', as the locktime 500 refers to the blogheight, and the current block height is less than that, the transaction will only be eligible to be broadcasted once the blockheight is more than 500. "
}

send_salary_again(){
    echo "Mining blocks, please be patient..."
bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 392 $miner_address

salary_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer sendrawtransaction $signed_hex)

bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 6 $miner_address
}


print_new_inference(){

echo " Now that we mined more blocks till the blockheight reached more than 500 ,and re-attempted the transaction it went through successfully."
}



print_wallet_balance(){

employee_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employee getbalance)
echo -e "Employee Balance :  $employee_balance "
employer_balance=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer getbalance)
echo -e " Employer Balance : $employer_balance "
}


create_op_return_tx(){
employee_utxo_info=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employee listunspent)
employee_utxo_txid=$(echo "$employee_utxo_info" | grep -o '"txid": "[^"]*' | grep -o '[^"]*$')
employee_utxo_vout=$(echo "$employee_utxo_info" | grep -o '"vout": [0-9]*' | grep -o '[0-9]*')
employee_change_addr=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employee getnewaddress legacy)

 OP_RETURN_DATA="I am now a wholecoiner"
 OP_RETURN_DATA="4920616d206e6f7720612077686f6c65636f696e6572"

op_return_raw_hex=$(bitcoin-cli -datadir=$bitcoin_data_dir -named createrawtransaction inputs='''[ { "txid": "'$employee_utxo_txid'", "vout": '$employee_utxo_vout' } ]''' outputs='''{ "data": "'$OP_RETURN_DATA'", "'$employee_change_addr'": 49.99999 }''')

signed_op_return_tx=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employee signrawtransactionwithwallet $op_return_raw_hex )
hex_value=$(echo "$signed_op_return_tx" | grep -o '"hex": "[^"]*' | grep -o '[^"]*$')

op_return_txid=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Employer sendrawtransaction $hex_value)

bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 6 $miner_address
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
check_and_create_wallet "Employee"
check_and_create_wallet "Employer"
generate_address
fund_miner
fund_employer
create_raw_salary_tx
print_inference
send_salary_again
print_new_inference
print_wallet_balance
create_op_return_tx
stop_bitcoind
delete_tmp_dir
