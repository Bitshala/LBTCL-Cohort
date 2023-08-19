#!/bin/bash

######### week 2 exercise ###########

# Function to delete regtest dir if already exists within /home/$USER/.bitcoin/
delete_regtest_dir() {
	echo -e "Deleting regtest directory if exists"

	if [ -d "/home/$USER/.bitcoin/regtest" ]; then
		rm -rf /home/$USER/.bitcoin/regtest
	fi
}

# Function to start bitcoind as daemon
start_bitcoind() {
	echo -e "Starting Bitcoin Core as daemon"
	# Start your Bitcoin Core Node on the background
	bitcoind -daemon
	# Wait for Node to initialize
	sleep 3
	# Bitcoin Core Node information
	bitcoin-cli -getinfo
}

create_wallets() {
	echo -e "Creating Miner and Trader wallets"
	# If Miner wallet doesn't exists, created
	if [ -d "$HOME/.bitcoin/regtest/wallets/Miner" ]; then
    	echo "Wallet 'Miner' already exists."
	else
    	bitcoin-cli createwallet "Miner"
    	echo "Wallet 'Miner' created."
	fi
	# If Trader wallet doesn't exists, created
	if [ -d "$HOME/.bitcoin/regtest/wallets/Trader" ]; then
    	echo "Wallet 'Trader' already exists."
	else
    	bitcoin-cli createwallet "Trader"
    	echo "Wallet 'Trader' created."
	fi
}

fund_miner_wallet() {
	echo -e "Fund Miner wallet"
	# load Miner wallet
	bitcoin-cli loadwallet Miner > /dev/null 2>&1
  	# get new address
	miner_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress)
	echo -e "new miner addr: $miner_addr"
	# mine blocks to fund miner's wallet with 150 btc -spendable-
	bitcoin-cli -rpcwallet=Miner generatetoaddress 103 $miner_addr > /dev/null 2>&1
	# get miner's wallet balance
	miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
	echo -e "wallet succesfully funded with $miner_balance btc"
}

create_parent_tx(){
	# select utxos and craft transaction
	utxo_txid_1=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0].txid')
	utxo_txid_2=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[1].txid')
	utxo_vout_1=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0].vout')
	utxo_vout_2=$(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[1].vout')
	# generate change address for Miner
	change_addr=$(bitcoin-cli -rpcwallet=Miner getrawchangeaddress)
	# generate Trader's new address
	trader_addr=$(bitcoin-cli -rpcwallet=Trader getnewaddress)
	# craft transaction
	parent_tx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1' }, { "txid": "'$utxo_txid_2'", "vout": '$utxo_vout_2' } ]''' outputs='''{ "'$trader_addr'": 70, "'$change_addr'": 29.99999 }''')
	# decode transaction for checking purposes
	bitcoin-cli -rpcwallet=Miner decoderawtransaction $parent_tx
}

sign_and_broadcast_parent_tx(){
	# sign tx
	signed_parent_tx=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$parent_tx | jq -r '.hex')
	# broadcast tx
	parent_txid=$(bitcoin-cli -named sendrawtransaction hexstring=$signed_parent_tx)
}

get_parent_tx_data(){
	# get tx data from mempool
	tx_data=$(bitcoin-cli getmempoolentry "$parent_txid")
	# get tx fees from mempool
	fees=$(echo "$tx_data" | jq -r '.fees.base')
	# get tx weight data from mempool
	weight=$(echo "$tx_data" | jq -r '.weight')
  
json_variable='{
	"input": [
		{
			"txid": "'$utxo_txid_1'",
			"vout": '$utxo_vout_1'
    	},
    	{
			"txid": "'$utxo_txid_2'",
			"vout": '$utxo_vout_2'
    	}
	],
	"output": [
    	{
    		"script_pubkey": "'$(bitcoin-cli -rpcwallet=Miner getaddressinfo "$miner_addr" | jq -r '.scriptPubKey')'",
    		"amount": '$miner_balance'
    	},
    	{
    		"script_pubkey": "'$(bitcoin-cli -rpcwallet=Trader getaddressinfo "$trader_addr" | jq -r '.scriptPubKey')'",
    		"amount": '$utxo_vout_1'
    	}
	],
	"Fees": '$fees',
	"Weight": '$weight'
}'

echo "$json_variable"
}

create_child_tx(){
	# generate Miner's new address
	miner_new_addr=$(bitcoin-cli -rpcwallet=Miner getnewaddress)
	# craft child tx
	child_raw_tx=$(bitcoin-cli -named createrawtransaction inputs='''[{ "txid": "'$parent_txid'", "vout": '1' }]'''  outputs='''{ "'$miner_new_addr'":   29.99998 }''')
}

sign_and_broadcast_child_tx(){
	# sign child tx
	signed_child_tx=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$child_raw_tx | jq -r '.hex')
	# broadcast child tx
	child_txid=$(bitcoin-cli -named sendrawtransaction hexstring=$signed_child_tx)
}

query_child_tx(){
	# get tx data from mempool
	echo -e "this is the child tx before bumping the parent tx:"
	bitcoin-cli getmempoolentry "$child_txid"
}

bump_parent_tx_with_rbf(){
	# craft bump tx
	rbf_raw_parent_tx=$(bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1', "sequence":2 }, { "txid": "'$utxo_txid_2'", "vout": '$utxo_vout_2' } ]'''   outputs='''{ "'$trader_addr'": 70, "'$change_addr'": 29.99989 }''')
	# sign bump tx
	rbf_signed_parent_tx=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$rbf_raw_parent_tx | jq -r '.hex')
	# broadcast bump tx
	rbf_txid_parent=$(bitcoin-cli -named sendrawtransaction hexstring=$rbf_signed_parent_tx)
}

query_child_tx(){
	# get tx data from mempool
	echo -e "this is the child tx after bumping the parent tx:"
	bitcoin-cli getmempoolentry "$child_txid"
}

print_explanation(){
	# print explanation on screen
	echo -e "child transaction got removed from mempool by RBF tx." 
	echo -e "parent tx is also removed from mempool"
}


delete_regtest_dir
start_bitcoind
create_wallets
fund_miner_wallet
create_parent_tx
sign_and_broadcast_parent_tx
get_parent_tx_data
create_child_tx
sign_and_broadcast_child_tx
query_child_tx
bump_parent_tx_with_rbf
query_child_tx
print_explanation