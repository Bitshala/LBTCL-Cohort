#!/usr/bin/env bash

# Global variables
SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
mining_reward_address=""

# Download bitcoin core, verify the file's sha, and extract to /usr/local/bin
download_bitcoin_core () {
	wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz \
		--no-clobber \
		--output-document=/tmp/bitcoin-25.0-x86_64-linux-gnu.tar.gz

	wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS \
		--no-clobber \
		--output-document=/tmp/SHA256SUMS

	wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc \
		--no-clobber \
		--output-document=/tmp/SHA256SUMS.asc

	cd /tmp
	if [[ $(sha256sum --ignore-missing --check SHA256SUMS) == "bitcoin-25.0-x86_64-linux-gnu.tar.gz: OK" ]]; then
		echo "Binary signature verification successful"
	fi

	sudo tar --extract \
		--file /tmp/bitcoin-25.0-x86_64-linux-gnu.tar.gz \
		--directory /usr/local/bin/
}

initiate () {
	# Move bitcoin config into location.
	cd ${SCRIPT_DIR}
	mkdir -p /home/bitcoin/.bitcoin/
	cp ./bitcoin.conf /home/bitcoin/.bitcoin/bitcoin.conf

	if test -f /home/bitcoin/.bitcoin/regtest/.lock; then
		echo "Bitcoind lock file exists, is it already running?"
	else
		bitcoind
	fi

	# Create wallets.
	create_wallet "Miner"
	create_wallet "Trader"

	# Create wallet address to fund.
	mining_reward_address=$( create_address "Miner" "Mining Reward" )

	echo "Mining reward address: ${mining_reward_address}"

	bitcoin-cli generatetoaddress 101 "${mining_reward_address}"

	echo "Block must have 100 confirmations before the reward will be sent, therefore we mine 101 blocks to start."

	miner_wallet_balance=$( bitcoin-cli -rpcwallet="Miner" getbalance )
	echo "Miner wallet balance: ${miner_wallet_balance}"

}

usage () {
	received_address=$( create_address "Trader" "Received" )

	echo "send 20 btc from Miner to Trader"
	amount_to_send="20"
	tx_id=$( bitcoin-cli -rpcwallet="Miner" sendtoaddress "${received_address}" "${amount_to_send}" )

	bitcoin-cli -rpcwallet="Miner" getmempoolentry "${tx_id}"

	bitcoin-cli generatetoaddress 1 "${mining_reward_address}"

	bitcoin-cli getrawtransaction "${tx_id}" true
	fee=$( bitcoin-cli -rpcwallet="Miner" gettransaction "55478c5fb39ea7965f7edc9c01bfc076dc592933a5c1dd9a9e270b529d2dada4" | jq '.fee' )
	blockheight=$( bitcoin-cli -rpcwallet="Miner" gettransaction "55478c5fb39ea7965f7edc9c01bfc076dc592933a5c1dd9a9e270b529d2dada4" | jq '.blockheight' )
	# Grab data on the transaction.
	echo "Transaction details"
	echo "txid: ${tx_id}"
	echo "<From, Amount>: ${mining_reward_address}, ${amount_to_send}"
	echo "<Send, Amount>: ${received_address}, ${amount_to_send}"
	echo "<Change, Amount>: ?, ? "
	echo "Fees: ${fee}"
	echo "Block: ${blockheight}"
	echo "Miner Balance: $( bitcoin-cli -rpcwallet="Miner" getbalance )"
	echo "Trader Balance: $( bitcoin-cli -rpcwallet="Trader" getbalance )"

}

# Creates a wallet with a name only if a wallet with that name doesn't exist.
# arg1: wallet name
create_wallet () {
	wallets=( $(bitcoin-cli listwallets) )
	if [[ "${wallets[*]}" =~ "$1" ]]; then
		echo "$1 wallet already exists"
	else
		bitcoin-cli createwallet "$1"
	fi
}

# Creates an address with a label only if an address with the label doesn't exist.
# arg1: wallet name
# arg2: address label
# return: address
create_address () {
	local address=""
	if bitcoin-cli -rpcwallet="$1" getaddressesbylabel "$2" > /dev/null ; then
		# address already exists
		address=$( bitcoin-cli -rpcwallet="$1" getaddressesbylabel "$2" | jq -r 'keys_unsorted | first' )
	else
		address=$( bitcoin-cli -rpcwallet="$1" getnewaddress "$2" )
	fi

	echo "${address}"
}

download_bitcoin_core
initiate
usage
