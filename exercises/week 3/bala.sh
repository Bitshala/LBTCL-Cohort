#!/bin/bash

##### Alias Definition #####
shopt -s expand_aliases
alias bcli="bitcoin-cli -datadir=/tmp/bitcointmpdata -named"
###########################

start_bitcoind () {
if [ ! -d "/tmp/bitcointmpdata" ]; then
	mkdir /tmp/bitcointmpdata
	printf "regtest=1\nfallbackfee=0.0001\nserver=1\ntxindex=1\nminrelaytxfee=0.00000001\nmintxfee=0.00000001\n" >> /tmp/bitcointmpdata/bitcoin.conf	
fi
if [ -e /tmp/bitcointmpdata/bitcoin.conf ]; then
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
		## Mining blocks with rewards into the miner wallet
		minerewards
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

if [ ! -d /tmp/bitcointmpdata/regtest/wallets/Alice ]; then
	if ( bcli createwallet wallet_name="Alice" ); then 
		echo -e "Wallet named Alice created successfully \n"
	else
		echo -e "Error creating Alice wallet \n"
	fi
else
	if [[ $(bcli listwallets | jq -r '.[] | select(.== "Alice")') == "Alice" ]]; then
		echo -e "Alice wallet already loaded \n"
	else 

		if ( bcli loadwallet filename=Alice );then
			echo -e "Alice wallet loaded successfully \n"
		fi
	fi
fi	


if [ ! -d /tmp/bitcointmpdata/regtest/wallets/Bob ]; then
	if ( bcli createwallet wallet_name="Bob" ); then 
		echo -e "Wallet named Bob created successfully \n"
	else
		echo -e "Error creating Bob wallet \n"
	fi
else
	if [[ $(bcli listwallets | jq -r '.[] | select(.== "Bob")') == "Bob" ]]; then
		echo -e "Bob wallet already loaded \n"
	else 

		if ( bcli loadwallet filename=Bob );then
			echo -e "Bob wallet loaded successfully \n"
		fi
	fi
fi	


} 

minerewards () {
mineaddress=$(bcli -rpcwallet=Miner getnewaddress address_type="legacy" label="Mining rewards")
exresult=$?
minedrewards=0
if [ $exresult == 0 ]; then
	while [ $minedrewards -le 150 ]
	do
	  if (bcli -rpcwallet=Miner generatetoaddress nblocks=101 address=$mineaddress >/dev/null); then 
		echo -e "101 Blocks mined \n"
		echo -e "Rewards are generated to the address: "$mineaddress"\n"
  	  minedrewards_float=$(bcli -rpcwallet=Miner listreceivedbylabel | jq -r '.[] | select(.label=="Mining rewards") | .amount'| bc)
  	  minedrewards=$(printf '%.*f\n' 0 $minedrewards_float)
	  else 
		echo -e "Error in generating blocks \n"
	  fi
	done
else 
	echo -e "Error in generating generating mining rewards \n"
fi
}

distribute_funds() {
receive_alice=$(bcli -rpcwallet=Alice getnewaddress label="receive" address_type="legacy")
receive_bob=$(bcli -rpcwallet=Bob getnewaddress label="receive" address_type="legacy")
change_miner=$(bcli -rpcwallet=Miner getrawchangeaddress address_type="legacy")

##### Selecting the two largest available UTXOs with the miner ##### 
utxo1_txid=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .txid')
utxo1_vout=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .vout')
utxo1_amount=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .amount')
utxo2_txid=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-2] | .txid')
utxo2_vout=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-2] | .vout')
utxo2_amount=$(bcli -rpcwallet=Miner listunspent | jq -s -r '.[] | sort_by(.amount) | .[-2] | .amount')
minerfees=0.05
distribute_amt=$(echo "scale=4; (($utxo1_amount+$utxo2_amount)/2)-($minerfees/2)" | bc)

### Creating raw transaction
distribute_rawtxhex=$(bcli -rpcwallet=Miner createrawtransaction inputs='''[ { "txid": "'$utxo1_txid'", "vout": '$utxo1_vout' }, { "txid":"'$utxo2_txid'", "vout": '$utxo2_vout'} ]''' outputs='''{ "'$receive_alice'":'$distribute_amt', "'$receive_bob'":'$distribute_amt' }''' )
distribute_signedtx=$(bcli -rpcwallet=Miner signrawtransactionwithwallet hexstring=$distribute_rawtxhex | jq -r '.hex')
distribute_txid=$(bcli -rpcwallet=Miner sendrawtransaction hexstring=$distribute_signedtx maxfeerate=0)
### Mining the transaction
distribute_mine=$(bcli -rpcwallet=Miner getnewaddress label="Mining rewards" address_type="legacy")
bcli -rpcwallet=Miner generatetoaddress nblocks=101 address=$distribute_mine >/dev/null
### Printing Balances
echo -e "\n ---------------------------- \n"
echo -e "Alice's wallet balance is"$(bcli -rpcwallet=Alice getbalance)
echo -e "Bob's wallet balance is"$(bcli -rpcwallet=Bob getbalance)
echo -e "\n ---------------------------- \n" 

}
# MULTI-SIG
test_mulsig () {
addr_alice_msig=$(bcli -rpcwallet=Alice getnewaddress label="multisig" address_type="legacy")
addr_bob_msig=$(bcli -rpcwallet=Bob getnewaddress label="multisig" address_type="legacy")
pubkey_alice_msig=$(bcli -rpcwallet=Alice getaddressinfo address=$addr_alice_msig | jq -r '.pubkey')
pubkey_bob_msig=$(bcli -rpcwallet=Bob getaddressinfo address=$addr_bob_msig | jq -r '.pubkey')
unsortedmultisig=$(bcli createmultisig nrequired=2 keys='''["'$pubkey_alice_msig'", "'$pubkey_bob_msig'"]''')

# Sorting Pubkeys
destdir=/tmp/bitcointmpdata/regtest/wallets/mpubkey.unsorted
sorteddir=/tmp/bitcointmpdata/regtest/wallets/mpubkey.sorted
sort_flag=0
sort_pubkey
declare -a sortedpubkeys=()
readarray -t sortedpubkeys < "$sorteddir"

if [[ $sort_flag == 1 ]]; then
	sortedmultisigdesc="sh(sortedmulti(2,${sortedpubkeys[0]},${sortedpubkeys[1]}))"
	sortedmultisigcks=$(bcli getdescriptorinfo $sortedmultisigdesc | jq -r '.checksum')
	sortedmultisigaddr=$(bcli deriveaddresses "$sortedmultisigdesc#$sortedmultisigcks" | jq -r '.[]')
	sortedmultisigdesc1="sh(sortedmulti(2,${sortedpubkeys[1]},${sortedpubkeys[0]}))"
	sortedmultisigcks1=$(bcli getdescriptorinfo $sortedmultisigdesc1 | jq -r '.checksum')
	sortedmultisigaddr1=$(bcli deriveaddresses "$sortedmultisigdesc1#$sortedmultisigcks1" | jq -r '.[]')
	echo -e "\n The unsorted multi sig address is \n" 
	echo $unsortedmultisig | jq -r '.address'
	echo -e "\n The sorted multisig address with keys in sorted order is \n" $sortedmultisigaddr
	echo -e "\n The sorted multisig address with keys in unsorted order is \n" $sortedmultisigaddr1
fi
rm $destdir
rm $sorteddir 
}

sort_pubkey () {

echo "$pubkey_alice_msig" > "$destdir"
echo "$pubkey_bob_msig" >> "$destdir"
sort "$destdir" > "$sorteddir"

cmpresult=$(cmp "$destdir" "$sorteddir")
if [[ $cmpresult == *"differ"* ]]; then
	sort_flag=1
fi
}

legacy_mulsig () {
addr_alice_msig=$(bcli -rpcwallet=Alice getnewaddress label="multisig" address_type="legacy")
addr_bob_msig=$(bcli -rpcwallet=Bob getnewaddress label="multisig" address_type="legacy")
pubkey_alice_msig=$(bcli -rpcwallet=Alice getaddressinfo address=$addr_alice_msig | jq -r '.pubkey')
pubkey_bob_msig=$(bcli -rpcwallet=Bob getaddressinfo address=$addr_bob_msig | jq -r '.pubkey')
msigdesc="sh(sortedmulti(2,$pubkey_alice_msig,$pubkey_bob_msig))"
msigcks=$(bcli getdescriptorinfo $msigdesc | jq -r '.checksum')
msigaddr=$(bcli deriveaddresses "$msigdesc#$msigcks" | jq -r '.[]')
echo -e $msigaddr
}

psbt () {
alice_txid=$(bcli -rpcwallet=Alice listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .txid')
alice_vout=$(bcli -rpcwallet=Alice listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .vout')
alice_amount=$(bcli -rpcwallet=Alice listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .amount')
bob_txid=$(bcli -rpcwallet=Bob listunspent |  jq -s -r '.[] | sort_by(.amount) | .[-1] | .txid')
bob_vout=$(bcli -rpcwallet=Bob listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .vout')
bob_amount=$(bcli -rpcwallet=Bob listunspent | jq -s -r '.[] | sort_by(.amount) | .[-1] | .amount')
alice_change=$(bcli -rpcwallet=Alice getrawchangeaddress address_type="legacy")
bob_change=$(bcli -rpcwallet=Bob getrawchangeaddress address_type="legacy")
minerfee=0.07

#calculate change outputs
c1=$(echo "$alice_amount > 10" | bc)
c2=$(echo "$bob_amount > 10" | bc)

if [ "$c1" = 1 ] && [ "$c2" = 1 ]; then
	alice_change_amount=$(echo "scale=4; $alice_amount-10-($minerfee/2)" | bc)
	bob_change_amount=$(echo "scale=4; $bob_amount-10-($minerfee/2)" | bc)
	msig_amount=20
else 
	alice_change_amount=$(echo "scale=4; $alice_amount-((90*$alice_amount)/100)-($minerfee/2)" | bc)
	boc_change_amount=$(echo "scale=4; $bob_amount-((90*$bob_amount)/100)-($minerfee/2" | bc)
	msig_amount=$(echo "scale=4; ($alice_amount+$bob_amount)-($alice_change_amount+$bob_change_amount)-$minerfee" | bc)
fi
##### Creating the PSBT #####
psbt_temp=$(bcli createpsbt inputs='''[ { "txid": "'$alice_txid'", "vout":'$alice_vout' }, { "txid": "'$bob_txid'", "vout":'$bob_vout' } ]''' outputs='''{ "'$msigaddr'": '$msig_amount', "'$alice_change'": '$alice_change_amount', "'$bob_change'": '$bob_change_amount' }''')
echo -e "The PSBT template is \n"
bcli decodepsbt psbt="$psbt_temp"
echo -e "\n"

#### Signing the PSBT #####
psbt_s_alice=$(bcli -rpcwallet=Alice walletprocesspsbt psbt="$psbt_temp" | jq -r '.psbt')
echo -e "\nThe PSBT signed by Alice is \n"
bcli decodepsbt psbt="$psbt_s_alice"

#### Signing the PSBT #####
psbt_s_bob=$(bcli -rpcwallet=Bob walletprocesspsbt psbt="$psbt_temp" | jq -r '.psbt')
echo -e "\nThe PSBT signed by Bob is \n"
bcli decodepsbt psbt="$psbt_s_bob"

##### Combining the PSBT #####
psbt_s_comb=$(bitcoin-cli -datadir=/tmp/bitcointmpdata combinepsbt '''["'$psbt_s_alice'", "'$psbt_s_bob'"]''')
echo -e "\nThe combined PSBT is \n"
bcli decodepsbt psbt="$psbt_s_comb"

##### Finalizing the PSBT #####
psbt_s_final=$(bcli finalizepsbt psbt="$psbt_s_comb" | jq -r '.hex')

#### Sending the Transaction Hex #####
bcli sendrawtransaction hexstring=$psbt_s_final maxfeerate=1
}
miningpsbt () {
### Mining the PSBT transaction
psbt_mine=$(bcli -rpcwallet=Miner getnewaddress label="Mining rewards" address_type="legacy")
bcli -rpcwallet=Miner generatetoaddress nblocks=101 address=$psbt_mine >/dev/null
### Printing Balances
echo -e "\n ---------------------------- \n"
echo -e "\nAlice's wallet balance is\n"$(bcli -rpcwallet=Alice getbalance)
echo -e "\nBob's wallet balance is\n"$(bcli -rpcwallet=Bob getbalance)
echo -e "The balance in the multisig address is \n"
bcli -rpcwallet=Alice decoderawtransaction $psbt_s_final | jq -r '.vout[1] | .value'
echo -e "\n ---------------------------- \n" 

}

returnpsbt () {
#Sending back the funds from the multisig wallet back to Alice and Bob
addr_alice_msig_receive=$(bcli -rpcwallet=Alice getnewaddress label="receive multisig" address_type="bech32")
addr_bob_msig_receive=$(bcli -rpcwallet=Bob getnewaddress label="receive multisig" address_type="bech32")
}

#start_bitcoind
#wallets
#distribute_funds
#test_mulsig
legacy_mulsig
psbt
#miningpsbt

