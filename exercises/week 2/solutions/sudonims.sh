#!/bin/bash

start_bitcoind() {
	echo "Starting node: "
	bitcoind -daemon
	sleep 10
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

create_parent_trx() {

	echo "============================= CREATING PARENT RAW TRX: "

	trxid=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	vouts=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	# echo ''''${trxid[1]}' '${vouts[1]}' '${trxid[2]}' '${vouts[2]}' '$1' '$2' ENND'''

	# echo '''[{"trxid": "'${trxid[1]}'", "vout": "'${vouts[1]}'"}, {"trxid": "'${trxid[2]}'", "vout": "'${vouts[2]}'"}]'''

	# echo '''{"'$1'": 70.0, "'$2'": 29.999}'''


	##GETTING JSON PARSE ERROR
	# bitcoin-cli -rpcwallet=Miner createrawtransaction '''"[{"txid": "'${trxid[1]}'", "vout": '${vouts[1]}' }, {"txid": "'${trxid[2]}'", "vout": '${vouts[2]}' }]"''' '''{"'$1'": 70.0, "'$2'": 29.999}''' '0' 'true'

	trxhex=`bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${trxid[1]}'", "vout": '${vouts[1]}'}, {"txid": "'${trxid[2]}'", "vout": '${vouts[2]}'}]''' outputs='''{"'$1'": 70.0, "'$2'": 29.999}''' replaceable=true`
}


sign_and_send_trx() {
	signedtrx=`bitcoin-cli -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`

	echo "SIGNED TRX: $signedtrx"

	bitcoin-cli -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx

	echo 
}

print_json_trx() {
	decoded_raw_trx=`bitcoin-cli -rpcwallet=Miner decoderawtransaction $signedtrx`

	echo $decoded_raw_trx

	trxid=`echo $decoded_raw_trx | jq -r '.txid'`

	inputs=`echo $decoded_raw_trx | jq -r '.vin | .[] | {txid: .txid, vout: .vout}'`

	outputs=`echo $decoded_raw_trx | jq -r '.vout | .[] | {script_pubkey: .scriptPubKey.hex, amount: .value}'`

	fees=`bitcoin-cli -rpcwallet=Miner gettransaction $trxid | jq -r '.fee' | sed 's/-//'`

	echo $decoded_raw_trx | jq --arg inputs "$inputs" --arg outputs "$outputs" --arg fees "$fees" '. | {input: $inputs, output: $outputs, fees: $fees, weight: .weight}'
}




# start_bitcoind

create_wallet Miner
create_wallet Trader

get_new_add Miner miner_address

miner_add=${add}

echo $miner_add

mine 103 $miner_add

# exit

get_new_add Trader trader_address

trader_add=${add}

change_add=`bitcoin-cli -rpcwallet=Miner getrawchangeaddress`

create_parent_trx $trader_add $change_add

parent_trx_hex=$trxhex

echo $parent_trx_hex
sign_and_send_trx Miner $parent_trx_hex

print_json_trx



