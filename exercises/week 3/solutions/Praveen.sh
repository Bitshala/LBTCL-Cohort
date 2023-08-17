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

# Function to create 2 wallets called Miner and Trader

create_wallets() {
	echo "**************************************"
	echo -e "${ORANGE}Creating Three wallets${NC}"
	echo "**************************************"
	# Create a wallet called Miner
	bitcoin-cli  -datadir=${HOME}/tmp_bitcoind_regtest -named createwallet wallet_name=Miner descriptors=false
	# Create a wallet called Alice
	bitcoin-cli  -datadir=${HOME}/tmp_bitcoind_regtest -named createwallet wallet_name=Alice descriptors=false

	# Create a wallet called Bob
	bitcoin-cli  -datadir=${HOME}/tmp_bitcoind_regtest -named createwallet wallet_name=Bob descriptors=false

}


fund_wallets() {

	echo "**************************************"
	echo -e "${ORANGE}Funding wallets${NC}"
	echo "**************************************"

	miner_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getnewaddress "Mining Reward" legacy)
	alice_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" getnewaddress "Funding wallet" legacy)
	bob_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" getnewaddress "Funding wallet" legacy)

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" generatetoaddress 103 $miner_address

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" sendtoaddress $alice_address 40
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" sendtoaddress $bob_address 40

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" generatetoaddress 1 $miner_address

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" getbalance
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" getbalance
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" getbalance
}


# Create a 2-of-2 Multisig address by combining public keys from Alice and Bob.

create_multisig() {
	echo "**************************************"
	echo -e "${ORANGE}Creating a 2-of-2 Multisig address${NC}"
	echo "**************************************"

	alice_multisig_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice getnewaddress legacy)
	bob_multisig_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Bob getnewaddress legacy)

	alice_pubkey=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" getaddressinfo $alice_multisig_address  | jq -r '.pubkey')
	bob_pubkey=$(bitcoin-cli  -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" getaddressinfo $bob_multisig_address | jq -r '.pubkey')

	multisig_address=$(bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest  createmultisig nrequired=2 keys='''["'$alice_pubkey'","'$bob_pubkey'"]''' | jq -r  '.address')

	echo "Multisig address of alice and bob: $multisig_address"
}

#Create a Partially Signed Bitcoin Transaction (PSBT) to fund the multisig address with 20 BTC, taking 10 BTC each from Alice and Bob, and providing correct change back to each of them.

create_psbt() {

	utxo_bob_txid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" listunspent | jq -r '.[0].txid')
	utxo_bob_vout=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" listunspent | jq -r '.[0].vout')
	utxo_alice_txid=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" listunspent | jq -r '.[0].txid')
	utxo_alice_vout=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" listunspent | jq -r '.[0].vout')
	bob_change_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" getrawchangeaddress legacy)
	alice_change_address=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" getrawchangeaddress legacy)



	psbt=$(bitcoin-cli -named -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" createpsbt inputs='''[{"txid" : "'$utxo_bob_txid'","vout":'$utxo_bob_vout'},{"txid" : "'$utxo_alice_txid'","vout":'$utxo_alice_vout'}]''' outputs='''[{"'$multisig_address'":20},{"'$bob_change_address'": 29.99999},{"'$alice_change_address'": 29.99999}]''' )

	# decode psbt to check structure
	echo "**************************************"
	echo -e "${ORANGE}PSBT Details ${NC}"
	echo "**************************************"
	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named  decodepsbt psbt=$psbt
	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named  analyzepsbt psbt=$psbt
	psbt_bob=$(bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" walletprocesspsbt psbt=$psbt | jq -r '.psbt')

	echo "**************************************"
	echo -e "${ORANGE}PSBT after Bob processed ${NC}"
	echo "**************************************"

	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" decodepsbt psbt=$psbt_bob
	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" analyzepsbt psbt=$psbt_bob
	psbt_alice=$(bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" walletprocesspsbt psbt=$psbt_bob | jq -r '.psbt')

	echo "**************************************"
	echo -e "${ORANGE}PSBT after Alice processed ${NC}"
	echo "**************************************"

	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named  analyzepsbt psbt=$psbt_alice
	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named  decodepsbt psbt=$psbt_alice
	psbt_hex=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named  finalizepsbt  psbt=$psbt_alice | jq -r '.hex')

	echo "**************************************"
	echo -e "${ORANGE}PSBT after finalzed ${NC}"
	echo "**************************************"

	bitcoin-cli -named -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Bob decoderawtransaction $psbt_hex

	echo "**************************************"
	echo -e "${ORANGE}Broadcast PSBT ${NC}"
	echo "**************************************"

	txid_psbt=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named sendrawtransaction hexstring=$psbt_hex)


	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Miner" generatetoaddress 1 $miner_address >> /dev/null

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" gettransaction $txid_psbt




}

create_spending_psbt() {

	echo "**************************************"
	echo -e "${ORANGE}Import Multisig address into Alice and Bob wallets ${NC}"
	echo "**************************************"

	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob"  -named addmultisigaddress  nrequired=2 keys='''["'$alice_pubkey'","'$bob_pubkey'"]'''
	bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice"  -named addmultisigaddress  nrequired=2 keys='''["'$alice_pubkey'","'$bob_pubkey'"]'''

	multisig_address_for_bob=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Bob getnewaddress legacy)
	multisig_address_for_alice=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice getnewaddress legacy)
	psbt_spend=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Bob -named createpsbt inputs='''[ { "txid": "'$txid_psbt'", "vout": 0 } ]''' outputs='''[{ "'$multisig_address_for_bob'": 12.99999 },{ "'$multisig_address_for_alice'": 6.99999 }]''')


	psbt_spend_bob=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" walletprocesspsbt $psbt_spend | jq -r '.psbt')
	psbt_spend_alice=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Alice" walletprocesspsbt $psbt_spend_bob | jq -r '.psbt')
	psbt_spend_hex=$(bitcoin-cli -regtest -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named finalizepsbt  psbt=$psbt_spend_alice | jq -r '.hex')



}

get_alice_bob_balance() {

	echo "**************************************"
	echo -e "${ORANGE}Alice & Bob Balances ${NC}"
	echo "**************************************"

	txid_psbt_spend=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet="Bob" -named sendrawtransaction hexstring=$psbt_spend_hex)
	bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Miner generatetoaddress 1 $miner_address >> /dev/null

	Alice_Balance=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Alice getbalance)
	Bob_Balance=$(bitcoin-cli -regtest  -datadir=${HOME}/tmp_bitcoind_regtest -rpcwallet=Bob getbalance)

	echo "Alice has: " $Alice_Balance
	echo "Bob has: " $Bob_Balance

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
fund_wallets
create_multisig
create_psbt
create_spending_psbt
get_alice_bob_balance
clean_up