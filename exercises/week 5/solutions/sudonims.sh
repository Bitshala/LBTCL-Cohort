#!/bin/bash

rm -rf ~/.bitcoin/sudonims
DATA_DIR=/home/$USER/.bitcoin/sudonims

start_bitcoind() {
	mkdir -p $DATA_DIR
	cat > $DATA_DIR/bitcoin.conf <<ENDL
regtest=1
fallbackfee=0.0001
server=1
txindex=1

[regtest]
rpcuser=test
rpcpassword=test
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
ENDL

	echo "Starting node: "
	bitcoind -datadir=$DATA_DIR -daemon
	sleep 5
}

create_wallet() {
	echo "Creating Wallet: $1"
	bitcoin-cli -datadir=$DATA_DIR -named createwallet wallet_name=$1 descriptors=false > /dev/null 2>&1 || exit
}

mine() {
	echo "Mining $1 times: "
	bitcoin-cli -datadir=$DATA_DIR generatetoaddress ${1} ${2} > /dev/null 2>&1
}

get_new_add() {
	add=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 getnewaddress legacy`
}

sign_and_send_trx() {
	signedtrx=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`
	trxid=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx`
	echo "Transaction sent: $trxid"
}

print_balance() {
	echo "Balance of $1"
	bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 getbalance "*" 6
}

fund_alice() {
	TRXIDS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 90.0, "'$2'": 9.99999}''' replaceable=true`

	sign_and_send_trx Miner $trxhex
}

alice_10_btc_trx() {
	TRXIDS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Alice listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Alice listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Alice -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[0]}'", "vout": '${VOUTS[0]}', "sequence": 10}]''' outputs='''{"'$1'": 10.0, "'$2'": 79.99999}''' replaceable=true`
}


start_bitcoind

create_wallet Miner
create_wallet Alice

get_new_add Miner miner_address
miner_add=${add}
get_new_add Miner change
miner_change=${add}

echo "Miner Address: ${miner_add}"
echo


mine 103 $miner_add


get_new_add Alice alice
alice_add=${add}
get_new_add Alice change
alice_change=${add}
echo "Alice address: $alice_add"

fund_alice $alice_add $miner_change

mine 6 $miner_add

print_balance Alice

alice_10_btc_trx $miner_add $alice_change
HEX=$trxhex

sign_and_send_trx Alice $HEX

echo "Transaction couldn't be sent because of sequence parameter denoting relative timelock"

mine 10 $miner_add

sign_and_send_trx Alice $HEX

mine 1 $miner_add

print_balance Alice

echo "Mining single block doesn't update balance as it needs 6 blocks for proper confirmation."

mine 5 $miner_add

print_balance Alice

bitcoin-cli -datadir=$DATA_DIR stop

exit