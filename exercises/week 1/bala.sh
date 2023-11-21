#!/bin/bash
# Package Requirements - bc, jq, awk 
################################################

echo -e "\n Downloading Bitcoin Core V25.0 \n"
echo -e "\n ------------------------------ \n"
wget -P ~/Bitshala/week1/ https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz

### Checking if the download was successful ### 

if ["$?" != 0]; then
	echo -e "\n Error in downloading the bitcoin core archive. Please try again \n"
	echo -e "\n ----------------------------------------------------------------"

	exit 1
else 
	echo -e "\n Bitcoin core archive was donloaded successfully \n"
	echo -e "\n ----------------------------------------------- \n"
fi
 
echo -e "\n Extracting Bitcoin Core v25.0 \n"
echo -e " ----------------------------- \n"
mkdir ~/Bitshala/week1/bitcoincorev25
tar -xvf bitcoin-25.0-x86_64-linux-gnu.tar.gz -C ~/Bitshala/week1/

if ["$?"!=0]; then
	echo -e "\n Error in extracting the bitcoin archive. Please try again \n"
	echo -e  " -------------------------------------------------------- \n"
	exit 1
else 
	echo -e "\n Bitcoin core archive was extracted successfully \n"
	echo -e " ----------------------------------------------- \n"
fi


echo -e "\n Verifying the downloaded Bitcoin Core \n"
echo -e " ---------------------------------------- \n"

### Downloading GPG files
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS >/dev/null 2>&1
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc >/dev/null 2>&1

git clone https://github.com/bitcoin-core/guix.sigs >/dev/null 2>&1
gpg --import guix.sigs/builder-keys/* >/dev/null 2>&1

#### Verifying the builder keys

sigverify=$(gpg --verify SHA256SUMS.asc 2>&1 | grep "Good signature" | wc -l)

if (( sigverify > 3 )); then #Atleast 3 coredev's keys checksout
	echo -e "\n Signature verification successful \n"
	echo -e " ---------------------------------- \n"

else
	echo -e "\n Signature verification failed \n"
	echo -e " ---------------------------------- \n"
	exit 1
fi

#### Verifying the checksum 

fv=$(sha256sum --ignore-missing --check SHA256SUMS 2>&1 | grep OK | wc -l)
if (( fv > 0 )); then
	echo -e "\n Cheksum verification successful \n"
	echo -e " ---------------------------------- \n"
	
else
	echo -e "\n  Chekcsum verification failed   \n"
	echo -e " ---------------------------------- \n"
	exit 1
fi


#### Copying files 

cp ~/Bitshala/week1//bitcoin-25.0/bin/ /usr/local/bin
if ["$?"!=0]; then
	echo -e "\n Error in copying binaries. Please try again \n"
	echo -e  " -------------------------------------------- \n"
	exit 1
else 
	echo -e "\n Bitcoin binaries copied successfully \n"
	echo -e " --------------------------------------- \n"
fi


#### Moving into .bitcoin directory 

if [ ! -d ~/.bitcoin ]
then 
	mkdir ~/.bitcoin
fi

#### Configuring the bitcoin.conf file 

if [ -e ~/.bitcoin/bitcoin.conf ]
then 
	n=$(cat ~/.bitcoin/bitcoin.conf | grep regtest=1 |wc -l)
	o=$(cat ~/.bitcoin/bitcoin.conf | grep fallbackfee=0.0001 |wc -l)
	p=$(cat ~/.bitcoin/bitcoin.conf | grep server=1 |wc -l)
	q=$(cat ~/.bitcoin/bitcoin.conf | grep txindex=1 |wc -l)
	
	if (( n < 1 )); then
		echo "regtest=1" >> ~/.bitcoin/bitcoin.conf
	fi
	
	if (( o < 1 )); then
		echo "fallbackfee=0.0001" >> ~/.bitcoin/bitcoin.conf
	fi

	if (( p < 1 )); then
		echo "server=1" >> ~/.bitcoin/bitcoin.conf
	fi

	if (( q < 1 )); then
		echo "txindex=1" >> ~/.bitcoin/bitcoin.conf
	fi
else
	echo -e "regtest=1 \nfallbackfee=0.0001 \nserver=1 \ntxindex=1 \n" >> ~/.bitcoin/bitcoin.conf
fi	


#### Starting the Bitcoin Deamon

echo -e "Starting the Bitcoin Daemon \n"
echo -e "--------------------------- \n"
g=$(/usr/local/bin/bitcoind -daemon 2>&1 | grep " Core is probably already running" | wc -l)

if ((g=1)); then
	echo -e "Core is already running \n"
	echo -e "----------------------- \n"
fi

#### Creating Wallets
if [ ! -d ~/.bitcoin/regtest/wallets/Miner ]
then
 
	bitcoin-cli -rpcwallet= createwallet Miner > /dev/null 2>&1
	echo -e "Miner wallet created \n"
	echo -e "--------------------- \n"
else
	echo -e "Miner Wallet already exists \n"
	echo -e "--------------------------- \n"
fi

if [ ! -d ~/.bitcoin/regtest/wallets/Trader ]
then
 
	bitcoin-cli -rpcwallet= createwallet Trader > /dev/null 2>&1
	echo -e "Trader wallet created \n"
	echo -e "--------------------- \n"
else
	echo -e "Trader Wallet already exists \n"
	echo -e "---------------------------- \n"
fi

#### Generating  Miner wallet address
maddr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward" "legacy")

#### Mining first reward 

x=0
i=0
blocks=1
while [ $x = 0 ]
do
	bitcoin-cli generatetoaddress $blocks $maddr 
	#g=$(bitcoin-cli -rpcwallet=Miner getbalancelistreceivedbylabel | grep amount | tr -dc '[. [:digit:]]' | xargs)
	g=$(bitcoin-cli -rpcwallet=Miner getbalance)
	gg=$(bc -l <<< $g)   ## Converting string to float
	echo $gg
	let "i++"
	if [[ $(bc <<< "$gg>0") == 1 ]]; then  ##comparing floats
		x=1
		bc=$(bitcoin-cli getblockcount)
		echo -e "No. of Blocks mined for a +ve reward" $bc "\n"
		echo -e "Mined reward is " $g "\n"
	fi
	
done

### Printing Miner reward Balance

echo -e "The balance in miner wallet is " $(bitcoin-cli -rpcwallet=Miner getbalance) 

### Transferring Mined rewards
taddr=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received" "legacy")
txid1=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $taddr 20 )
echo -e " The transaction details are \n"
echo -e " --------------------------- \n"
bitcoin-cli getmempoolentry $txid1

### Confirming the transaction 
bitcoin-cli -rpcwallet=Miner -generate


### Collecting and printing transaction details
echo -e " The transaction id is : "$txid1"\n"
txhex=$(bitcoin-cli -rpcwallet=Trader gettransaction $txid1 | jq -r '.hex')
inputtxid=$(bitcoin-cli decoderawtransaction $txhex | jq -r '.vin |.[] .txid')
inputtxhex=$(bitcoin-cli -rpcwallet=Miner gettransaction $inputtxid | jq -r '.hex')
echo -e "The input address to the transaction is :"$(bitcoin-cli -rpcwallet=Miner gettransaction $inputtxid |jq -r '.details |.[] .address')"\n"
inpamt=$(bitcoin-cli -rpcwallet=Miner gettransaction $inputtxid | jq -r '.amount')
echo -e "The input amount to the transaction is :"$inpamt"\n"
echo -e "The output address of the transaction is :"$(bitcoin-cli -rpcwallet=Trader gettransaction $txid1 | jq -r '.details |.[] .address')"\n"
opamt=$(bitcoin-cli -rpcwallet=Trader gettransaction $txid1 | jq -r '.amount')
echo -e "The output amount of the tranasction is :"$opamt"\n"
echo -e "The address to which the change is paid back :"$(bitcoin-cli decoderawtransaction $txhex | jq -r '.vout | .[] | select(.n==0) | .scriptPubKey.address')"\n"
chgamt=$(bitcoin-cli decoderawtransaction $txhex |jq -r '.vout | .[] | select(.n==0) | .value')
echo -e "The change amount is :"$chgamt"\n"
minerfee=$(awk -vOFMT=%10.7f 'BEGIN{print '$inpamt'-'$opamt'-'$chgamt'}') #-vOMFT is used to change float format
echo -e "The Miner fees is :"$minerfee"\n"
echo -e "Block height of the transaction :"$(bitcoin-cli -rpcwallet=Trader gettransaction $txid1 | jq -r '.blockheight')"\n"
echo -e "Miner's wallet balance is :"$(bitcoin-cli -rpcwallet=Miner getbalance)"\n"
echo -e "Trader's wallet balance is :"$(bitcoin-cli -rpcwallet=Trader getbalance)"\n"

