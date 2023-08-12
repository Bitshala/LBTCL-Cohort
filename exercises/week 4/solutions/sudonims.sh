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
	bitcoin-cli -datadir=$DATA_DIR -named createwallet wallet_name=$1 descriptors=false || exit
}

mine() {
	bitcoin-cli -datadir=$DATA_DIR generatetoaddress ${1} ${2} > /dev/null 2>&1
}

get_new_add() {
	add=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 getnewaddress legacy`
}

sign_and_send_trx() {
	signedtrx=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`

	echo "SIGNED TRX: $signedtrx"

	trxid=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx`

}

fund_employer() {
	TRXIDS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 90.0, "'$2'": 9.99999}''' replaceable=true`

	sign_and_send_trx Miner $trxhex
}

create_salary_trx() {
	TRXIDS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Employer listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Employer listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Employer -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[0]}'", "vout": '${VOUTS[0]}'}]''' outputs='''{"'$1'": 40.0, "'$2'": 49.99999 }''' locktime=500 replaceable=true`

}

print_balance() {
	echo "Balance of $1"
	bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 getbalance "*" 6
}

create_2_2_multisig_address() {
	pub1=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 getaddressinfo $2 | jq -r '.pubkey'`
	pub2=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$3 getaddressinfo $4 | jq -r '.pubkey'`

	multisig_add=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=$1 -named createmultisig nrequired=2 keys='''["'$pub1'", "'$pub2'"]''' | jq -r '.address'`
}






start_bitcoind

create_wallet Miner
create_wallet Employee
create_wallet Employer

get_new_add Miner miner_address
miner_add=${add}
get_new_add Miner change
miner_change=${add}

echo "Miner Address: ${miner_add}"
echo


echo "Mining 103 times: "
echo
mine 103 $miner_add


get_new_add Employer employer
employer_add=${add}
get_new_add Employer employer
employer_change=${add}

get_new_add Employee salary
employee_add=${add}
get_new_add Employee change
employee_change=${add}


fund_employer $employer_add $miner_change

mine 103 $miner_add

create_salary_trx $employee_add $employer_change
salary_trxhex=$trxhex

mine 500 $miner_add

sign_and_send_trx Employer $salary_trxhex

echo '''

=========================================================

We get
error code: -26
error message:
non-final

the transaction sort of gets rejected by mempool before 500 blocks are mined
=========================================================

'''

mine 100 $miner_add

print_balance Employee
print_balance Employer 

bitcoin-cli -datadir=$DATA_DIR stop
exit





echo "Alice add: ${alice_add} Bob Address: ${bob_add}"
echo

change_add=`bitcoin-cli -datadir=$DATA_DIR -rpcwallet=Miner getrawchangeaddress`
echo "Change Address for Miner: ${change_add}"
echo

fund_alice_n_bob $alice_add $bob_add $change_add

mine 103 $miner_add

create_2_2_multisig_address Alice $alice_add Bob $bob_add

echo $multisig_add

create_psbt_to_multisig $multisig_add

psbt_txid=$txid

mine 101 $miner_add

create_psbt_spend_from_multisig $multisig_add $psbt_txid 

# mine 101 $miner_add

print_balance Alice
print_balance Bob

bitcoin-cli -datadir=$DATA_DIR stop

# I don't think Alice or Bob can be poorer or richer, as it is completely dependant on how the PSBTs were made...
