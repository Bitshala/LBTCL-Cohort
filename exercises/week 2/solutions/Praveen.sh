#!/bin/bash

echo "Let there be a node"
ORANGE='\033[35m'
NC='\033[0m' # No Color


# Function to delete regtest dir if already exists within /Users/$USER/Library/Application\ Support/Bitcoin
setup_regtest_env() {
	echo "**************************************"
	echo -e "${ORANGE}Setup regtest directory ${NC}"
	echo "**************************************"

	# delete  ~/tmp_bitcoind_regtest if it exists
	if [ -d ~/tmp_bitcoind_regtest ]; then
		rm -rf ~/tmp_bitcoind_regtest
	fi


	mkdir ~/tmp_bitcoind_regtest
	cd ~/tmp_bitcoind_regtest

	touch bitcoin.conf

	echo "regtest=1" >> bitcoin.conf
	echo "fallbackfee=0.00001" >> bitcoin.conf
	echo "server=1" >> bitcoin.conf
	echo "txindex=1" >> bitcoin.conf
	echo "daemon=1" >> bitcoin.conf


}

# Function to start bitcoind in the background and run the last command
start_bitcoind() {
	echo "**************************************"
	echo -e "${ORANGE}Starting bitcoind${NC}"
	echo "**************************************"
	# Start bitcoind in the background
	bitcoind -daemon -regtest  -datadir=${HOME}/tmp_bitcoind_regtest  -conf=${HOME}/tmp_bitcoind_regtest/bitcoin.conf
	# Wait for 10 seconds
	sleep 4
	# Now you can run bitcoin-cli getinfo
	#bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -getinfo
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest getblockchaininfo

}

# Function to create 2 wallets called Miner and Trader

create_wallets() {
	echo "**************************************"
	echo -e "${ORANGE}Creating two wallets${NC}"
	echo "**************************************"
	# Create a wallet called Miner
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest createwallet "Miner"
	# Create a wallet called Trader
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest createwallet "Trader"
}

# Function to fund miner wallet

fund_miner_wallets() {
	echo "**************************************"
	echo -e "${ORANGE}Generate an address for miner and mine blocks${NC}"
	echo "**************************************"

	mineraddress=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getnewaddress "Mining Reward")
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" generatetoaddress 103 $mineraddress
	echo -e "\n \n \n"
	read -n 1 -s -r -p "  Press any key to continue"
	echo -e "\n \n \n"
	original_balance=$(bitcoin-cli  -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getbalance)
	echo "Original balance in $mineraddress $original_balance"
}

create_rbf_transaction() {
	utxo1_txid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .txid')
	utxo2_txid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" listunspent | jq -r '.[1] | .txid')

	utxo1_vout=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" listunspent | jq -r '.[0] | .vout')
	utxo2_vout=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" listunspent | jq -r '.[1] | .vout')

	traderaddress=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Trader" getnewaddress )
	changeaddress=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getrawchangeaddress )

	parentrawtxhex=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -named  -rpcwallet="Miner" createrawtransaction inputs='''[ { "txid": "'$utxo1_txid'", "vout": '$utxo1_vout'}, { "txid": "'$utxo2_txid'", "vout": '$utxo2_vout'} ]''' outputs='''{ "'$traderaddress'": 70, "'$changeaddress'": 29.9999 }''')
	signedparenttx=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -named  -rpcwallet="Miner"  signrawtransactionwithwallet hexstring=$parentrawtxhex | jq -r '.hex')
	parentxid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -named  -rpcwallet="Miner" sendrawtransaction hexstring=$signedparenttx)

}


print_json() {
	json=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" decoderawtransaction $parentrawtxhex)

	inputtx1=$(echo $json | jq -r '.vin[0].txid')
	inputtx2=$(echo $json | jq -r '.vin[1].txid')
	inputvout1=$(echo $json | jq -r '.vin[0].vout')
	inputvout2=$(echo $json | jq -r '.vin[1].vout')
	trader_script_pubkey=$(echo $json | jq -r '.vout[0].scriptPubKey.hex')
	miner_script_pubkey=$(echo $json | jq -r '.vout[1].scriptPubKey.hex')
	trader_amount=$(echo $json | jq -r '.vout[0].value')
	miner_amount=$(echo $json | jq -r '.vout[1].value')
	weight=$(echo $json | jq -r '.weight')

	txfees=$(bitcoin-cli -named -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getmempoolentry $(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getrawmempool | jq -r '.[]')  )
	fees=$(echo $txfees | jq -r '.fees.base')

	echo "**************** JSON of Parent Transaction *********************"
	parent_json='''{ "input": [ { "txid": "'$inputtx1'", "vout": '$inputvout1'}, { "txid": "'$inputtx2'", "vout": '$inputvout2'} ], "output": [ {"script_pubkey": "'$trader_script_pubkey'", "amount": "'$trader_amount'"}, {"script_pubkey": "'$miner_script_pubkey'", "amount": "'$miner_amount'"}] , "weight": "'$weight'", "fees": "'$fees'" }'''

	echo $parent_json | jq -r
	echo -e "\n*******************************************************\n"
	echo -e "Here is the original Parent transaction in the mempool \n"
	echo -e "\n*******************************************************\n"
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getrawmempool
	echo -e "\n \n \n"
	read -n 1 -s -r -p "Press any key to continue"
}

create_child_transaction() {

	new_miner_address=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getnewaddress)
	childrawtxhex=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest  -rpcwallet="Miner" createrawtransaction inputs='''[ { "txid": "'$parentxid'", "vout": 1} ]''' outputs='''{ "'$new_miner_address'": 29.9995 }''')
	signedchildtx=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest  -rpcwallet="Miner"  signrawtransactionwithwallet hexstring=$childrawtxhex | jq -r '.hex')
	childtxid=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest  -rpcwallet="Miner" sendrawtransaction hexstring=$signedchildtx)

	echo -e "\n*******************************************************\n"
	echo -e "\n Here is newly minted child transaction in the mempool \n"
	echo -e "\n*******************************************************\n"
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getrawmempool
	echo -e "\n \n \n"
	read -n 1 -s -r -p "Press any key to continue"
}

bump_parent_transaction() {
	parentrbftx=$(bitcoin-cli -named -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner"  createrawtransaction inputs='''[ { "txid": "'$utxo1_txid'", "vout": '$utxo1_vout', "sequence": 1}, { "txid": "'$utxo2_txid'", "vout": '$utxo2_vout', "sequence": 1} ]''' outputs='''{ "'$traderaddress'": 70, "'$changeaddress'": 29.9991 }''')
	signedparentrbftx=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest  -rpcwallet="Miner"  signrawtransactionwithwallet hexstring=$parentrbftx | jq -r '.hex')
	parenrbftxid=$(bitcoin-cli -regtest -named -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" sendrawtransaction hexstring=$signedparentrbftx)

	echo -e "\n*************************************************************************************************************************** \n"
	echo -e "\n The fee bump on parent transaction knocked out both the inital parent and the child transaction from the mempool \n"
	echo -e "\n*************************************************************************************************************************** \n"
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getrawmempool
	echo -e "\n \n \n"
	read -n 1 -s -r -p "  Press any key to continue to continue cleanup"
	echo -e "\n \n \n"
}

clean_up() {
	echo "****************************************"
	echo -e "${ORANGE}Cleaning up${NC}"
	echo "****************************************"
	# Stop bitcoind
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest stop
	# Delete the regtest directory
	rm -rf ~/tmp_bitcoind_regtest


}


setup_regtest_env
start_bitcoind
create_wallets
fund_miner_wallets
create_rbf_transaction
print_json
create_child_transaction
bump_parent_transaction
clean_up