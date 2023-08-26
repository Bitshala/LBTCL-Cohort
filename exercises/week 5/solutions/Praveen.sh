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
	chown -R $USER ~/tmp_bitcoind_regtest
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
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest getblockchaininfo

}

# Function to create 2 wallets called Miner and Alice

create_wallets() {
	echo "**************************************"
	echo -e "${ORANGE}Creating Two wallets${NC}"
	echo "**************************************"
	# Create a wallet called Miner
	bitcoin-cli  -datadir=${HOME}/tmp_bitcoind_regtest -named createwallet wallet_name=Miner

	# Create a wallet called Alice
	bitcoin-cli  -datadir=${HOME}/tmp_bitcoind_regtest -named createwallet wallet_name=Alice

}

# Fund the wallets

fund_miner_alice() {
	echo "**************************************"
	echo -e "${ORANGE}Funding Miner and Alice${NC}"
	echo "**************************************"
	# Fund the Miner wallet
	miner_address=$(bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner getnewaddress)
	alice_address=$(bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice getnewaddress)
	bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner generatetoaddress 104 $miner_address >> /dev/null

	# Fund the Alice wallet
	bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner sendtoaddress $alice_address 100 >> /dev/null
	bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner generatetoaddress 1 $miner_address >> /dev/null

}

miner_alice_balance() {
	echo -e "\n**************************************"
	echo -e "${ORANGE}Miner/Alice Balances:${NC}"
	echo "*******************************************"

	Miner_Balance=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner getbalance)
	Alice_Balance=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice getbalance)

	echo "Miner has: " $Miner_Balance
	echo "Alice has: " $Alice_Balance
}

timelock_transaction() {
	echo -e "\n**************************************"
	echo -e "${ORANGE}Creating a timelock transaction${NC}"
	echo "*******************************************"

	utxo_txid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice listunspent | jq -r '.[0] | .txid')
	utxo_vout=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice listunspent | jq -r '.[0] | .vout')
	sequence=10



	# Create a raw transaction
	rawtxhex=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -named  -rpcwallet=Alice createrawtransaction inputs='''[ { "txid": "'$utxo_txid'", "vout": '$utxo_vout',  "sequence":'$sequence'} ]''' outputs='''{"'$miner_address'":10, "'$alice_address'":89.9999}''')
	signedtx=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -named -rpcwallet=Alice signrawtransactionwithwallet hexstring=$rawtxhex | jq -r '.hex')
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice sendrawtransaction $signedtx

	echo "***********************************************************************************************************************************************"
	echo -e "${ORANGE}As you can see above, we are getting the error preventing transmission because of timelock, so let us generate the blocks needed to release transaction:${NC}"
	echo "***********************************************************************************************************************************************"

	dots=""

	for i in {1..5}; do
		dots="${dots}."
		printf "\rMining blocks till timelock$dots"
		sleep 1
	done

	bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner generatetoaddress 10 $miner_address >> /dev/null
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice sendrawtransaction $signedtx
	bitcoin-cli -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner generatetoaddress 1 $miner_address >> /dev/null

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
fund_miner_alice
miner_alice_balance
timelock_transaction
miner_alice_balance
clean_up