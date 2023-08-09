#!/bin/bash

rm -rf ~/.bitcoin/regtest

start_bitcoind() {
	echo "Starting node: "
	bitcoind -daemon
	sleep 5
}

create_wallet() {
	echo "Creating Wallet: $1"
	bitcoin-cli createwallet $1
}

mine() {
	bitcoin-cli generatetoaddress ${1} ${2}
}

get_new_add() {
	add=`bitcoin-cli -rpcwallet=$1 getnewaddress "$2"`
}

sign_and_send_trx() {
	signedtrx=`bitcoin-cli -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`

	echo "SIGNED TRX: $signedtrx"

	trxid=`bitcoin-cli -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx`

}

fund_alice_n_bob() {

	echo "============================= CREATING PARENT RAW TRX: "

	TRXIDS=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 45.0, "'$2'": 45.0, "'$3'": 9.99999}''' replaceable=true`

	sign_and_send_trx Miner $trxhex
}

# print_json_trx() {
# 	decoded_raw_trx=`bitcoin-cli -rpcwallet=Miner decoderawtransaction $signedtrx`

# 	trxid=`echo $decoded_raw_trx | jq -r '.txid'`

# 	inputs=`echo $decoded_raw_trx | jq -r '.vin | .[] | {txid: .txid, vout: .vout}'`

# 	outputs=`echo $decoded_raw_trx | jq -r '.vout | .[] | {script_pubkey: .scriptPubKey.hex, amount: .value}'`

# 	fees=`bitcoin-cli -rpcwallet=Miner gettransaction $trxid | jq -r '.fee' | sed 's/-//'`

# 	echo $decoded_raw_trx | jq --arg inputs "$inputs" --arg outputs "$outputs" --arg fees "$fees" '. | {input: $inputs, output: $outputs, fees: $fees, weight: .weight}'
# }

print_balance() {
	bitcoin-cli -rpcwallet=$1 getbalance "*" 6
}

create_2_2_multisig_address() {
	pub1=`bitcoin-cli -rpcwallet=$1 getaddressinfo $2 | jq -r '.pubkey'`
	pub2=`bitcoin-cli -rpcwallet=$3 getaddressinfo $4 | jq -r '.pubkey'`

	multisig_add=`bitcoin-cli -rpcwallet=$1 -named createmultisig nrequired=2 keys='''["'$pub1'", "'$pub2'"]''' | jq -r '.address'`
}

create_psbt_to_multisig() {
	echo "CREATING PSBT A======================>"
	TRXID_ALICE=($(bitcoin-cli -rpcwallet=Alice listunspent | jq -r '.[] | .txid'))
	VOUT_ALICE=($(bitcoin-cli -rpcwallet=Alice listunspent | jq -r '.[] | .vout'))

	TRXID_BOB=($(bitcoin-cli -rpcwallet=Bob listunspent | jq -r '.[] | .txid'))
	VOUT_BOB=($(bitcoin-cli -rpcwallet=Bob listunspent | jq -r '.[] | .vout'))

	get_new_add Alice change
	alice_change_add=$add
	get_new_add Bob change
	bob_change_add=$add

	psbt=`bitcoin-cli -named createpsbt inputs='''[{"txid": "'${TRXID_ALICE[0]}'", "vout": '${VOUT_ALICE[0]}'}, {"txid": "'${TRXID_BOB[0]}'", "vout": '${VOUT_BOB[0]}'}]''' outputs='''[{"'$1'": 20}, {"'${alice_change_add}'": 34.99999}, {"'${bob_change_add}'": 34.99999}]'''`

	alice_sign=`bitcoin-cli -rpcwallet=Alice walletprocesspsbt ${psbt} | jq -r '.psbt'`
	bob_sign=`bitcoin-cli -rpcwallet=Bob walletprocesspsbt ${alice_sign}`

	status=`echo ${bob_sign} | jq -r '.complete'`
	echo $bob_sign

	[ "$status" == "true" ] && echo "PSBT Signed completely" || echo "PSBT is not completely signed" 

	psbt=`echo ${bob_sign} | jq -r '.psbt'`
	finalized=`bitcoin-cli finalizepsbt ${psbt} | jq -r '.hex'`

	echo "PSBT Hex: ${finalized}"

	txid=`bitcoin-cli sendrawtransaction "$finalized"`

}





start_bitcoind

create_wallet Miner
create_wallet Alice
create_wallet Bob

get_new_add Miner miner_address

miner_add=${add}

echo "Miner Address: ${miner_add}"
echo


echo "Mining 103 times: "
echo
mine 105 $miner_add

# exit

get_new_add Alice alice_add
alice_add=${add}
get_new_add Bob bob_add
bob_add=${add}

echo "Alice add: ${alice_add} Bob Address: ${bob_add}"
echo

change_add=`bitcoin-cli -rpcwallet=Miner getrawchangeaddress`
echo "Change Address for Miner: ${change_add}"
echo

fund_alice_n_bob $alice_add $bob_add $change_add

mine 103 $miner_add

create_2_2_multisig_address Alice $alice_add Bob $bob_add

echo $multisig_add

create_psbt_to_multisig $multisig_add

psbt_txid=$txid

mine 101 $miner_add

print_balance Alice
print_balance Bob




