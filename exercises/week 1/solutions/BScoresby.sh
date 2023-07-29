#!/bin/bash
#SETUP

#Download Bitcoin core binaries and hashes and signatures
wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz

wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS

wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc

#Download and import gpg keys of Bitcoin core maintainers
git clone https://github.com/bitcoin-core/guix.sigs

gpg --import guix.sigs/builder-keys/*

#Verify release file checksum is in SHA256SUMS
ANSWER=$(sha256sum --ignore-missing --check SHA256SUMS)

if [[ ( $ANSWER == "bitcoin-25.0-x86_64-linux-gnu.tar.gz: OK" ) ]]; then
	echo "File is verified"
else
	echo "Not able to verify file, examine checksums at https://bitcoincore.org"
	exit 1
fi

#Verify that the checksums file is PGP signed by Andrew Chow, Ben Carman, Michael Ford, and Gloria Zhao 

gpg --verify SHA256SUMS.asc &> signatures.txt

if grep -E 'gpg: Good signature from "Andrew Chow <andrew@achow101.com>" [unknown]|Primary key fingerprint: 1528 1230 0785 C964 44D3  334D 1756 5732 E08E 5E41' signatures.txt  
then
	CHOW="good"
	echo "Good signature from Andrew Chow"
else
	CHOW="bad"
	echo "No good signature"
fi

if grep -E 'gpg: Good signature from "Ben Carman <benthecarman@live.com>" [unknown]|Primary key fingerprint: 0AD8 3877 C1F0 CD1E E9BD  660A D7CC 770B 81FD 22A8' signatures.txt
then
	CARMAN="good"
	echo "Good signature from Ben Carman"
else
	CARMAN="bad"
	echo "No good signature"
fi

if grep -E 'gpg: Good signature from "Michael Ford (bitcoin-otc) <fanquake@gmail.com>" [unknown]|Primary key fingerprint: E777 299F C265 DD04 7930  70EB 944D 35F9 AC3D B76A' signatures.txt
then
	FANQUAKE="good"
	echo "Good signature from Michael Ford"
else
	FANQUAKE="bad"
	echo "No good signature"
fi

if grep -E 'gpg: Good signature from "Gloria Zhao <gloriazhao@berkeley.edu>" [unknown]|Primary key fingerprint: 6B00 2C6E A3F9 1B1B 0DF0  C9BC 8F61 7F12 00A6 D25C' signatures.txt
then
	ZHAO="good"
	echo "Good signature from Gloria Zhao"
else
	ZHAO="bad"
	echo "No good signature"
fi

if [[ ( $CHOW == "good" && $CARMAN == "good" && $FANQUAKE == "good" && $ZHAO == "good" ) ]];
then
	echo "Binary signature verification successful"
else
	echo "Please check signatures at https://bitcoincore.org"
	exit 1
fi

#Extract binaries
tar -xf bitcoin-25.0-x86_64-linux-gnu.tar.gz

#Copy binaries to /usr/local/bin
sudo cp -R ./bitcoin-25.0 /usr/local/bin/

sudo mv /usr/local/bin/bitcoin-25.0 /usr/local/bin/bitcoin

#INITIATE

#Create bitcoin.conf file with configs
cd /home/$USER/

mkdir .bitcoin

cd /home/$USER/.bitcoin/

> bitcoin.conf

echo "regtest=1
  fallbackfee=0.0001
  server=1
  txindex=1" >> bitcoin.conf
  
#Start Bitcoind
cd /usr/local/bin/bitcoin/bin/

./bitcoind -daemon

echo "Waiting for Bitcoin to start..."

sleep 3

#Create two wallets

./bitcoin-cli -named createwallet wallet_name="Miner"
./bitcoin-cli -named createwallet wallet_name="Trader"

#Generate one address from Miner wallet with label "Mining Reward"

MINER1=`./bitcoin-cli -rpcwallet=Miner getnewaddress -label="Mining Reward"`

#Mine 101 new blocks to address
./bitcoin-cli generatetoaddress 101 "$MINER1"

#Because block rewards are not spendable until 100 blocks after they have been mined, it is necessary to mine 101 blocks to get any spendable bitcoin. 

MINERBALANCE=`./bitcoin-cli -rpcwallet=Miner getbalance`

echo "$MINERBALANCE"

#Usage
#Create a receiving address labeled "Received" from Trader wallet
TRADER1=`./bitcoin-cli -rpcwallet=Trader getnewaddress -label="Received"`

TRADERTXID1=`./bitcoin-cli -rpcwallet=Miner sendtoaddress "$TRADER1" 20`

sleep 1

MEMTXINFO=`./bitcoin-cli getmempoolentry $TRADERTXID1`

echo "$MEMTXINFO"

#Confirm transaction by mining 1 block
./bitcoin-cli generatetoaddress 1 $MINER1

#Fetch transaction details and print into terminal
./bitcoin-cli -rpcwallet=Trader gettransaction $TRADERTXID1 false true &> /home/$USER/.bitcoin/txinfo.txt

echo "Fetching transaction info and printing to terminal..."

#Get txid and store in variable TXID
#NOTE: I opted to use sed, grep, and bash commands to collect the required data and store it in variables for pretty printing, rather than jq. Mostly because I was curious to see if I could do it.
TXIDLINE=`grep -m 1 '"txid"' /home/$USER/.bitcoin/txinfo.txt`

TXID="$(cut -d'"' -f4 <<<"$TXIDLINE")"

echo "txid: $TXID"

#Get input info and store as variables VINADDR and VINAMOUNT
VIN=`sed -n '/"vin"/{ n; n; p }' /home/$USER/.bitcoin/txinfo.txt`

VIN="$(cut -d '"' -f4 <<<"$VIN")"

VININFO=`/usr/local/bin/bitcoin/bin/bitcoin-cli -rpcwallet=Miner gettransaction $VIN false true`

VINADDR=`sed -n -e 's/.*\("address": \)/\1/p' <<<"$VININFO"`

VINADDR=`sed -n '1!p' <<<"$VINADDR"`

VINADDR="$(cut -d '"' -f4 <<<"$VINADDR")"

VINAMOUNT="$(cut -d' ' -f4 <<<"$VININFO")"

VINAMOUNT="${VINAMOUNT%%,*}"

VINAMOUNT="${VINAMOUNT:2}"

echo "<From, Amount>: $VINADDR, $VINAMOUNT"

#Get output info and store as variables VOUTADDR and VOUTAMOUNT
VOUTADDR=`sed -n '/"n": 1,/{ n; n; n; n; n; p }' /home/$USER/.bitcoin/txinfo.txt`

VOUTADDR="$(cut -d '"' -f4 <<<"$VOUTADDR")"

VOUTAMOUNT=`sed -n -e '/"n": 1,/{ x; p; d; }' -e x /home/$USER/.bitcoin/txinfo.txt`

VOUTAMOUNT="$(cut -d':' -f2 <<<"$VOUTAMOUNT")"

VOUTAMOUNT="${VOUTAMOUNT%%,*}"

VOUTAMOUNT="${VOUTAMOUNT:1}"

echo "<Send, Amount>: $VOUTADDR, $VOUTAMOUNT"

#Get ouput info and store as variables CHNGADDR and CHNGAMOUNT
CHNGADDR=`sed -n '/"vout": /{ n; n; n; n; n; n; n; n; p }' /home/$USER/.bitcoin/txinfo.txt`

CHNGADDR=`sed -n '1!p' <<<"$CHNGADDR"`

CHNGADDR=`sed -n '1!p' <<<"$CHNGADDR"`

CHNGADDR="$(cut -d '"' -f4 <<<"$CHNGADDR")"

CHNGAMOUNT=`sed -n '/"vout": /{ n; n; p }' /home/$USER/.bitcoin/txinfo.txt`

CHNGAMOUNT=`sed -n '1!p' <<<"$CHNGAMOUNT"`

CHNGAMOUNT=`sed -n '1!p' <<<"$CHNGAMOUNT"`

CHNGAMOUNT="$(cut -d ':' -f2 <<<"$CHNGAMOUNT")"

CHNGAMOUNT="${CHNGAMOUNT%%,*}"

CHNGAMOUNT="${CHNGAMOUNT:1}"

echo "<Change, Amount>: $CHNGADDR, $CHNGAMOUNT"

#Get fees and store as variable FEES
FEES=$(echo "$VINAMOUNT - $VOUTAMOUNT - $CHNGAMOUNT" | bc)

echo "Fees: $FEES BTC"

#Get blockheight and store in variable BLOCK
BLOCKLINE=`grep -m 1 '"blockheight"' /home/cleophas/.bitcoin/txinfo.txt`

BLOCK="$(cut -d' ' -f4 <<<"$BLOCKLINE")"

BLOCK="$(cut -d',' -f1 <<<"$BLOCK")"

echo "Block: $BLOCK"

#Get Miner Balance and store as MINERBAL
MINERBAL=`./bitcoin-cli -rpcwallet=Miner getbalance`

echo "Miner Balance: $MINERBAL"

#Get Trader Balance and store as TRADERBAL
TRADERBAL=`./bitcoin-cli -rpcwallet=Trader getbalance`

echo "Trader Balance: $TRADERBAL"
