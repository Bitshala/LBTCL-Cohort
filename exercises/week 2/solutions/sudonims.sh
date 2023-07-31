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

create_parent_trx() {

	echo "============================= CREATING PARENT RAW TRX: "

	TRXIDS=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	# echo ''''${trxid[1]}' '${vouts[1]}' '${trxid[2]}' '${vouts[2]}' '$1' '$2' ENND'''

	# echo '''[{"trxid": "'${trxid[1]}'", "vout": "'${vouts[1]}'"}, {"trxid": "'${trxid[2]}'", "vout": "'${vouts[2]}'"}]'''

	# echo '''{"'$1'": 70.0, "'$2'": 29.999}'''


	##GETTING JSON PARSE ERROR
	# bitcoin-cli -rpcwallet=Miner createrawtransaction '''"[{"txid": "'${trxid[1]}'", "vout": '${vouts[1]}' }, {"txid": "'${trxid[2]}'", "vout": '${vouts[2]}' }]"''' '''{"'$1'": 70.0, "'$2'": 29.999}''' '0' 'true'

	trxhex=`bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 70.0, "'$2'": 29.99999}''' replaceable=true`
}

create_child_trx() {
	echo "============================== CREATING CHILD RAW TRX: "
	
	trxhex=`bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${trxid}'", "vout": 1}]''' outputs='''{"'$1'": 29.99998}''' replaceable=true`
}

create_parent_rbf_trx() {
	echo "============================== CREATING PARENT RBF TRX: "
	trxhex=`bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 70.0, "'$2'": 29.99989}''' replaceable=true`
}


sign_and_send_trx() {
	signedtrx=`bitcoin-cli -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`

	echo "SIGNED TRX: $signedtrx"

	trxid=`bitcoin-cli -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx`

}

print_json_trx() {
	decoded_raw_trx=`bitcoin-cli -rpcwallet=Miner decoderawtransaction $signedtrx`

	trxid=`echo $decoded_raw_trx | jq -r '.txid'`

	inputs=`echo $decoded_raw_trx | jq -r '.vin | .[] | {txid: .txid, vout: .vout}'`

	outputs=`echo $decoded_raw_trx | jq -r '.vout | .[] | {script_pubkey: .scriptPubKey.hex, amount: .value}'`

	fees=`bitcoin-cli -rpcwallet=Miner gettransaction $trxid | jq -r '.fee' | sed 's/-//'`

	echo $decoded_raw_trx | jq --arg inputs "$inputs" --arg outputs "$outputs" --arg fees "$fees" '. | {input: $inputs, output: $outputs, fees: $fees, weight: .weight}'
}




start_bitcoind

create_wallet Miner
create_wallet Trader

get_new_add Miner miner_address

miner_add=${add}

echo "Miner Address: ${miner_add}"
echo


echo "Mining 103 times: "
echo
mine 103 $miner_add

# exit

get_new_add Trader trader_address

trader_add=${add}
echo "Trader Address: ${trader_add}"
echo

change_add=`bitcoin-cli -rpcwallet=Miner getrawchangeaddress`
echo "Change Address for Miner: ${change_add}"
echo

create_parent_trx $trader_add $change_add
parent_trx_hex=$trxhex
echo "Parent trx hex: ${parent_trx_hex}"
echo
sign_and_send_trx Miner $parent_trx_hex
parent_txid=$trxid
echo "Sent parent txid: ${parent_txid}"
echo

print_json_trx
echo

get_new_add Miner new_add

new_miner_add=${add}
echo "New Miner Address for child trx: ${new_miner_add}"
echo

create_child_trx $new_miner_add
child_trx_hex=$trxhex
echo "Child trx hex: ${child_trx_hex}"
echo
sign_and_send_trx Miner $child_trx_hex
child_txid=$trxid
echo "Sent child transaction: ${trxid}"
echo

bitcoin-cli -rpcwallet=Miner getmempoolentry $child_txid


create_parent_rbf_trx $trader_add $change_add
parent_rbf_trx_hex=$trxhex
echo "Parent RBF trx hex: ${parent_rbf_trx_hex}"
echo
sign_and_send_trx Miner $parent_rbf_trx_hex
parent_rbf_txid=$trxid
echo "Sent parent RBF txid: ${parent_rbf_txid}"
echo

bitcoin-cli -rpcwallet=Miner getmempoolentry $child_txid
echo
echo "The new parent RBF transaction replaces the old parent transaction and as a result old parent tx is discarded. This old parent tx is used by the child tx as input hence child is also cascadingly discarded from mempool."
echo

bitcoin-cli stop



