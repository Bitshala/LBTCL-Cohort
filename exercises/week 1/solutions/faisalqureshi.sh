

echo "Let there be a node"

wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-arm64-apple-darwin.dmg
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS

VERSION="25.0"
DMG_FILE="bitcoin-${VERSION}-x86_64-apple-darwin.dmg"
CHECKSUMS_FILE="SHA256SUMS"
SIGNATURE_FILE="SHA256SUMS.asc"
gpg --keyserver keyserver.ubuntu.com --recv-keys 01EA5486DE18A882D4C2684590C8019E36C2E964
gpg --verify "${SIGNATURE_FILE}"

if shasum -a 256 -c "${CHECKSUMS_FILE}" 2>/dev/null | grep -q "${DMG_FILE}: OK"; then
    echo "✅ Binary signature verification successful! Happy verifying! 😃"
else
    echo "❌ Binary signature verification unsuccessful! Please check the integrity of your binary. 😞"
fi

cd /Users/$USER/Library/Application\ Support/Bitcoin

touch bitcoin.conf

echo "regtest=1" >> bitcoin.conf
echo "fallbackfee=0.0001" >> bitcoin.conf
echo "server=1" >> bitcoin.conf
echo "txindex=1" >> bitcoin.conf

# Start bitcoind in the background
bitcoind -daemon
# Wait for 10 seconds
sleep 10
# Now you can run bitcoin-cli getinfo
bitcoin-cli -getinfo

# Creating Miner Wallet

bitcoin-cli  createwallet Miner


# Creating Trader Wallet

bitcoin-cli  createwallet Trader


# Loading Miner Wallet

bitcoin-cli  loadwallet Miner

# Generating an address for Miner wallet with the label “Mining Reward”

miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")

# Mining Blocks

bitcoin-cli  -rpcwallet=Miner generatetoaddress 101 $miner_address

# Checking the balance to verify it is in immature state 

bitcoin-cli  -rpcwallet=Miner getwalletinfo   

# Creating an address labeled “Received” from Trader Wallet

trader_address=$(bitcoin-cli  -rpcwallet=Trader getnewaddress "Received")

# Loading Trader Wallet

bitcoin-cli  loadwallet Trader

# Printing the Miner Wallet Balance

bitcoin-cli -rpcwallet=Miner getbalance


# Sending a transaction paying 20 BTC from Miner wallet to Trader wallet


txid=$(bitcoin-cli   -rpcwallet=Miner sendtoaddress $trader_address 20)

# Fetching the unconfirmed transaction

bitcoin-cli  getmempoolentry $txid

# Confirming the transaction by creating one more block

bitcoin-cli -rpcwallet=Miner -generate 1 


# Retrieving relevant information regarding the transaction

transaction_info=$(bitcoin-cli -rpcwallet=Miner gettransaction $txid)

: '
Printing the following details:
- Transaction ID (txid)
- Trader’s Address
- Input Amount
- Sent Amount
- Change Back Amount
- Fees
- Block height
- Miner Balance
- Trader Balance
'
format_amount() {
  printf "%.8f" $(echo "$1" | sed 's/^-//')
}

txid=$(echo "$transaction_info" | grep -oE '"txid": "[^"]+"' | awk -F'"' '{print $4}')
to_address=$(echo "$transaction_info" | grep -oE '"address": "[^"]+"' | awk -F'"' 'NR==1{print $4}')

sent_amount=$(format_amount $(echo "$transaction_info" | grep -oE '"amount": -?[0-9.]+' | awk -F': ' '{print $2}'))
fee=$(format_amount $(echo "$transaction_info" | grep -oE '"fee": -?[0-9.]+' | awk -F': ' '{print $2}'))
received_amount=$(echo "scale=8; $sent_amount - $fee" | bc)
block_height=$(echo "$transaction_info" | grep -oE '"blockheight": [0-9]+' | awk -F': ' '{print $2}')

miner_balance=$(bitcoin-cli -datadir=/Volumes/SANDISK_64/bitcoin -rpcwallet=Miner getbalance)
trader_balance=$(bitcoin-cli -datadir=/Volumes/SANDISK_64/bitcoin -rpcwallet=Trader getbalance)

# Update balances after the transaction

miner_balance=$(echo "scale=8; $miner_balance - $sent_amount + $received_amount" | bc)
trader_balance=$(echo "scale=8; $trader_balance + $received_amount" | bc)

echo "txid: $txid"
echo "<From, Amount>: <Miner's Address>, $sent_amount BTC"
echo "<Send, Amount>: <$to_address>, $received_amount BTC"
echo "<Change, Amount>: <Miner's Address>, $fee BTC"
echo "Fees: $fee BTC"
echo "Block: Block height $block_height"
echo "Miner Balance: $miner_balance BTC"
echo "Trader Balance: $trader_balance BTC"

# Printing Miner’s address and amount sent

bitcoin-cli txid="b52e3b99f370273a9096010b171bba66282a520f9bb50517402579172d94fd68"
transaction_info=$(bitcoin-cli -datadir=/Volumes/SANDISK_64/bitcoin -rpcwallet=Miner getrawtransaction $txid true)

format_amount() {
  printf "%.8f" $(echo "$1" | sed 's/^-//')
}


vout_values=$(echo "$transaction_info" | grep -oE '"value": [0-9.]+' | awk -F': ' '{print $2}')
sender_amount=$(format_amount $(echo "$vout_values" | awk 'NR==1{print $1}'))


sender_address=$(echo "$transaction_info" | grep -oE '"address": "[^"]+"' | awk -F'"' 'NR==1{print $2}')


echo "Miner's Address: $sender_address, Amount: $sender_amount BTC"
