#!/bin/bash
shopt -s expand_aliases
alias bcli="bitcoin-cli -datadir=/tmp/bitcointmpdata -named"
start_bitcoind () {
if [ ! -d "/tmp/bitcointmpdata" ]; then
	mkdir /tmp/bitcointmpdata
	printf "regtest=1\nfallbackfee=0.0001\nserver=1\ntxindex=1\nminrelaytxfee=0.00000001\nmintxfee=0.00000001\n" >> /tmp/bitcointmpdata/bitcoin.conf	

elif [ -e /tmp/bitcointmpdata/bitcoin.conf ]; then
	echo -e "Removing the existing config file and creating a new one \n"
	rm /tmp/bitcointmpdata/bitcoin.conf
	printf "regtest=1\nfallbackfee=0.0001\nserver=1\ntxindex=1\nminrelaytxfee=0.00000001\nmintxfee=0.00000001\n" >> /tmp/bitcointmpdata/bitcoin.conf
	echo -e "The new bitcoind configurations are: \n"
	cat /tmp/bitcointmpdata/bitcoin.conf
fi

if startresult=$(bitcoind -datadir=/tmp/bitcointmpdata -daemon 2>&1); then
	waitforbitcoind 
elif [[ $startresult == *"probably already running"* ]]; then
	echo -e "Bitcoin core is already running\n"
	previousdatadir=$(find / -type f -name "debug.log" -mtime -1 2>&1 | grep -v "Permission denied")
	datadirectory=$(cat $previousdatadir|grep datadir)
	datadirectory2=${datadirectory##*datadir=}
	datadirectory3=$(echo "$datadirectory2" | tr -d '"')
	## Stopping the already running instance of bitcoin
	stopbitcoind 
	## Restarting bitcoind  
	echo -e "Restarting bitcoind \n"
	bitcoind -datadir=/tmp/bitcointmpdata -daemon
	waitforbitcoind

else
	echo -e "Error in starting Bitcoind. Please check the error below \n" $startresult
fi
}
waitforbitcoind () {
n=0
while ! bcli -getinfo
do 
	if [[ $n>3 ]]; then
		echo -e "Error in starting Bitcoin Core \n"
		exit 1
	fi
	sleep 1
	let "n+=1"
done
echo -e "--------------------------\nBitcoin core started successfully\n------------------------------\n"
}

stopbitcoind () {
processid=$(pidof bitcoind)
if [ -z $processid ]; then
	echo -e "Bitcoind doesn't exit \n"
	return 0
else
	bitcoin-cli -datadir=$datadirectory3 stop
	result1=$?
	tail --pid=$processid -f /dev/null
	result2=$?
	if [[ $result1 -eq 0 && $result2 -eq 0 ]]; then 
		echo -e "Bitcoin Core Stopped \n"
		return 0
	else 
		kill $processid
		if [-z $(pidof bitcoind) ]; then 
			echo -e "Bitcoin Core stopped \n"
			return 0
		else
			echo -e "Error while stopping bitcoin core. Please check debug.log \n"
			exit 1
		fi
	fi
fi
}

wallets () {
#Checking if wallets are loaded 

if [ ! -d /tmp/bitcointmpdata/regtest/wallets/Miner ]; then
	if ( bcli createwallet wallet_name="Miner" ); then 
		echo -e "Waller named Miner created successfully \n"
		## Mining blocks with rewards into the miner wallet ##
		minerewards Miner
	else
		echo -e "Error creating Miner wallet \n"
	fi
else
	if [[ $(bcli listwallets | jq -r '.[] | select(.== "Miner")') == "Miner" ]]; then
		echo -e "Miner wallet already loaded \n"
	else
			if ( bcli loadwallet filename=Miner );then
				echo -e "Miner wallet loaded successfully \n"
			fi
	fi

fi	
if [ ! -d /tmp/bitcointmpdata/regtest/wallets/Trader ]; then
	if ( bcli createwallet wallet_name="Trader" ); then 
		echo -e "Wallet named Trader created successfully \n"
		## Mining blocks with rewards into the miner wallet ##
	else
		echo -e "Error creating Trader wallet \n"
	fi
else
	if [[ $(bcli listwallets | jq -r '.[] | select(.== "Trader")') == "Trader" ]]; then
		echo -e "Trader wallet already loaded \n"
	else 

		if ( bcli loadwallet filename=Trader );then
			echo -e "Trader wallet loaded successfully \n"
		fi
	fi
fi	

} 

minerewards () {
walletname=$1
mineaddress=$(bcli -rpcwallet=$walletname getnewaddress address_type="legacy" label="Mining rewards")
exresult=$?
minedrewards=0
if [ $exresult == 0 ]; then
	while [ $minedrewards -le 150 ]
	do
	  if (bcli -rpcwallet=$walletname generatetoaddress nblocks=101 address=$mineaddress >/dev/null); then 
		echo -e "101 Blocks mined \n"
		echo -e "Rewards are generated to the address: "$mineaddress"\n"
	  minedrewards_float=$(bcli -rpcwallet=$walletname listreceivedbylabel | jq -r '.[] | select(.label=="Mining rewards") | .amount'| bc)
	  minedrewards=$(printf '%.*f\n' 0 $minedrewards_float)
	 else 
		echo -e "Error in generating blocks \n"
	fi
	done
else 
	echo -e "Error in generating new address in Miner wallet \n"
fi

}

parenttransaction () {
utxo1_txid=$(bcli -rpcwallet=Miner listunspent | jq -r '.[-1] | select(.amount>=50) | .txid')
utxo1_vout=$(bcli -rpcwallet=Miner listunspent | jq -r '.[-1] | select(.amount>=50) | .vout')

utxo2_txid=$(bcli -rpcwallet=Miner listunspent | jq -r '.[-2] | select(.amount>=50) | .txid')
utxo2_vout=$(bcli -rpcwallet=Miner listunspent | jq -r '.[-2] | select(.amount>=50) | .vout')
recipient=$(bcli -rpcwallet=Trader getnewaddress address_type="legacy" label="receive")
changeaddress=$(bcli -rpcwallet=Miner getrawchangeaddress address_type="legacy")

if [ -z "$utxo1_txid" ] | [ -z "$utxo2_txid" ]; then
	echo -e "UTXOs with balance >=50 can't be found \n"
	exit 1
fi
rawtxhex=$(bcli -rpcwallet=Miner createrawtransaction inputs='''[ { "txid": "'$utxo1_txid'", "vout": '$utxo1_vout', "sequence": 1 }, {"txid": "'$utxo2_txid'", "vout": '$utxo2_vout', "sequence": 1} ]''' outputs='''{ "'$recipient'": 70, "'$changeaddress'": 29.7}''')
signedtx=$(bcli -rpcwallet=Miner signrawtransactionwithwallet hexstring=$rawtxhex | jq -r '.hex')
parenttxid=$(bcli sendrawtransaction hexstring=$signedtx maxfeerate=0)
}
	
collecttxinfo () {
#### Collecting transaction information to publish ####
tradertxid=$(bcli -rpcwallet=Trader gettransaction $parenttxid | jq -r '.txid')
tradervout=$(bcli -rpcwallet=Trader gettransaction $parenttxid | jq -r '.details[0] | .vout')
tscriptpubkey=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$signedtx | jq -r '.vout[0] | .scriptPubKey' | jq '.')
utxo1_hex=$(bcli -rpcwallet=Miner gettransaction $utxo1_txid | jq -r '.hex')
mscriptpubkey1=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$utxo1_hex | jq -r '.vout[0] | .scriptPubKey' | jq '.')
amount1=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$signedtx | jq -r '.vout[0] | .value')
amount2=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$signedtx | jq -r '.vout[1] | .value')
utxo2_hex=$(bcli -rpcwallet=Miner gettransaction $utxo2_txid | jq -r '.hex')
mscriptpubkey2=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$utxo2_hex | jq -r '.vout[0] | .scriptPubKey')
fees=$(awk -vOFMT=%10.8f 'BEGIN{print '$(bcli -rpcwallet=Miner gettransaction txid=$parenttxid |jq -r '.fee')' }')
weight=$(bcli -rpcwallet=Miner decoderawtransaction hexstring=$signedtx | jq -r '.weight')
echo -e "The Parent transaction details are \n"
echo '{"input":[{"txid":"'$utxo1_txid'", "vout":"'$utxo1_vout'"},{"txid":"'$tradertxid'", "vout":"'$tradervout'"}],"output":[{"script pubkey":'$mscriptpubkey1', "amount":"'$amount2'"}, {"script pubkey":'$tscriptpubkey', "amount":"'$amount1'"}],  "Fees": "'$fees'", "Weight": "'$weight'" }' | jq '.'
}
childtx () {
#### Creating new child transaction
childtxaddress=$(bcli -rpcwallet=Miner getnewaddress label="child tx" address_type="legacy")
childrawtx=$(bcli -rpcwallet=Miner createrawtransaction inputs=''' [ { "txid":"'$parenttxid'", "vout":'1' } ] ''' outputs='''{ "'$childtxaddress'":29.65 }''')
signedchildtx=$(bcli -rpcwallet=Miner signrawtransactionwithwallet hexstring=$childrawtx | jq -r '.hex')
childtxid=$(bcli -rpcwallet=Miner sendrawtransaction hexstring=$signedchildtx maxfeerate=0)
echo -e "The mempool entry of the child transaction before RBF is as follows \n"
bcli -rpcwallet=Miner getmempoolentry $childtxid
echo -e "\n the transaction details of the child transaction before RBF is \n"
bcli -rpcwallet=Miner gettransaction $childtxid
}

rbfparent () {
rbfparentrawtx=$(bcli -rpcwallet=Miner createrawtransaction inputs='''[ { "txid": "'$utxo1_txid'", "vout": '$utxo1_vout', "sequence": 1 }, {"txid": "'$utxo2_txid'", "vout": '$utxo2_vout', "sequence": 1} ]''' outputs='''{ "'$recipient'": 70, "'$changeaddress'": 29.6}''')
signedrbftx=$(bcli -rpcwallet=Miner signrawtransactionwithwallet hexstring=$rbfparentrawtx | jq -r '.hex')
rbfparenttxid=$(bcli -rpcwallet=Miner sendrawtransaction hexstring=$signedrbftx maxfeerate=0)
echo -e "The mempool entry of the parent transaction after RBF is as follows \n"
bcli -rpcwallet=Miner getmempoolentry $parenttxid
echo -e "\n -------------------------------------------------------------------\n"
echo -e "\n The details of the parent transaction after RBF is as follows \n"
bcli -rpcwallet=Miner gettransaction $parenttxid
echo -e "\n -------------------------------------------------------------------\n"
echo -e "\n The mempool entry of the RBF parent transaction is \n"
bcli -rpcwallet=Miner getmempoolentry $rbfparenttxid
echo -e "\n -------------------------------------------------------------------\n"
echo -e "\n The mempool entry of the child transaction after RBF is \n"
bcli -rpcwallet=Miner getmempoolentry $childtxid
echo -e "\n -------------------------------------------------------------------\n"
echo -e "\n The transaction details of the child transaction after RBF \n"
bcli -rpcwallet=Miner gettransaction $childtxid
echo -e "\n -------------------------------------------------------------------\n"
echo -e "\n -------------------------------------------------------------------\n"
echo -e "The following observations can be made about the parent, child and RBFed transactions \n1. After RBF, the parent transaction is updated with a walletconflict \n2.The child transaction and the original parent transaction is evicted from the mempool after the parent transaction is RBFed\n"
}
#start_bitcoind 

#wallets
parenttransaction
collecttxinfo
childtx
rbfparent

