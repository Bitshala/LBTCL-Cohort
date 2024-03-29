#!/bin/bash


rm -rf ~/.bitcoin/sudonims

start_bitcoind() {
	mkdir -p /home/$USER/.bitcoin/sudonims
	cat > /home/$USER/.bitcoin/sudonims/bitcoin.conf <<ENDL
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
	bitcoind -datadir=/home/$USER/.bitcoin/sudonims -daemon
	sleep 5
}

create_wallet() {
	echo "Creating Wallet: $1"
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -named createwallet wallet_name=$1 descriptors=false || exit
}

mine() {
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims generatetoaddress ${1} ${2}
}

get_new_add() {
	add=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 getnewaddress legacy`
}

sign_and_send_trx() {
	signedtrx=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 signrawtransactionwithwallet "$2" | jq -r '.hex'`

	echo "SIGNED TRX: $signedtrx"

	trxid=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtrx`

}

fund_alice_n_bob() {

	echo "============================= CREATING PARENT RAW TRX: "

	TRXIDS=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
	VOUTS=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))

	trxhex=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'${TRXIDS[1]}'", "vout": '${VOUTS[1]}'}, {"txid": "'${TRXIDS[2]}'", "vout": '${VOUTS[2]}'}]''' outputs='''{"'$1'": 45.0, "'$2'": 45.0, "'$3'": 9.99999}''' replaceable=true`

	sign_and_send_trx Miner $trxhex
}

# print_json_trx() {
# 	decoded_raw_trx=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner decoderawtransaction $signedtrx`

# 	trxid=`echo $decoded_raw_trx | jq -r '.txid'`

# 	inputs=`echo $decoded_raw_trx | jq -r '.vin | .[] | {txid: .txid, vout: .vout}'`

# 	outputs=`echo $decoded_raw_trx | jq -r '.vout | .[] | {script_pubkey: .scriptPubKey.hex, amount: .value}'`

# 	fees=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner gettransaction $trxid | jq -r '.fee' | sed 's/-//'`

# 	echo $decoded_raw_trx | jq --arg inputs "$inputs" --arg outputs "$outputs" --arg fees "$fees" '. | {input: $inputs, output: $outputs, fees: $fees, weight: .weight}'
# }

print_balance() {
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 getbalance "*" 6
}

create_2_2_multisig_address() {
	pub1=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 getaddressinfo $2 | jq -r '.pubkey'`
	pub2=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$3 getaddressinfo $4 | jq -r '.pubkey'`

	multisig_add=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=$1 -named createmultisig nrequired=2 keys='''["'$pub1'", "'$pub2'"]''' | jq -r '.address'`
}

create_psbt_to_multisig() {
	echo "CREATING PSBT A======================>"
	TRXID_ALICE=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice listunspent | jq -r '.[] | .txid'))
	VOUT_ALICE=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice listunspent | jq -r '.[] | .vout'))

	TRXID_BOB=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob listunspent | jq -r '.[] | .txid'))
	VOUT_BOB=($(bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob listunspent | jq -r '.[] | .vout'))

	get_new_add Alice change
	alice_change_add=$add
	get_new_add Bob change
	bob_change_add=$add

	psbt=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -named createpsbt inputs='''[{"txid": "'${TRXID_ALICE[0]}'", "vout": '${VOUT_ALICE[0]}'}, {"txid": "'${TRXID_BOB[0]}'", "vout": '${VOUT_BOB[0]}'}]''' outputs='''[{"'$1'": 20}, {"'${alice_change_add}'": 34.99999}, {"'${bob_change_add}'": 34.99999}]'''`

	alice_sign=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice walletprocesspsbt ${psbt} | jq -r '.psbt'`
	bob_sign=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob walletprocesspsbt ${alice_sign}`

	status=`echo ${bob_sign} | jq -r '.complete'`
	echo $bob_sign

	[ "$status" == "true" ] && echo "PSBT Signed completely" || echo "PSBT is not completely signed" 

	psbt=`echo ${bob_sign} | jq -r '.psbt'`
	finalized=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims finalizepsbt ${psbt} | jq -r '.hex'`

	echo "PSBT Hex: ${finalized}"

	txid=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims sendrawtransaction "$finalized"`

	echo "PSBT to multisig txid: ${txid}"

}

create_psbt_spend_from_multisig() {
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice -named addmultisigaddress nrequired=2 keys='''["'$pub1'","'$pub2'"]'''
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob -named addmultisigaddress nrequired=2 keys='''["'$pub1'","'$pub2'"]'''
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice -named importaddress address="$1" rescan=false
	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob -named importaddress address="$1" rescan=false


	psbt=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -named createpsbt inputs='''[{"txid": "'$2'", "vout": 0}]''' outputs='''[{"'${alice_change_add}'": 9.99999}, {"'${bob_change_add}'": 9.99999}]'''`

	alice_sign=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Alice walletprocesspsbt ${psbt} | jq -r '.psbt'`
	bob_sign=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Bob walletprocesspsbt ${alice_sign}`

	status=`echo ${bob_sign} | jq -r '.complete'`

	[ "$status" == "true" ] && echo "PSBT Signed completely" || echo "PSBT is not completely signed" 

	bob_sign=`echo $bob_sign | jq -r '.psbt'`

	bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims decodepsbt $bob_sign

	finalized=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims finalizepsbt ${bob_sign} | jq -r '.hex'`

	echo "PSBT Hex: ${finalized}"

	txid=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims sendrawtransaction "$finalized"`

	echo "PSBT multisig spend txid: ${txid}"
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

change_add=`bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims -rpcwallet=Miner getrawchangeaddress`
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

bitcoin-cli -datadir=/home/$USER/.bitcoin/sudonims stop

# I don't think Alice or Bob can be poorer or richer, as it is completely dependant on how the PSBTs were made...
