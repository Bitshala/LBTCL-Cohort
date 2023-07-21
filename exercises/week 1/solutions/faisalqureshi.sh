LBTCL 


# Verifying  the Binary

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

#Navigating to the bitcoin core directory

cd /Volumes/SANDISK_64/bitcoin

#Creating a bitcoin.conf file

nano bitcoin.conf

 regtest=1
 fallbackfee=0.0001
 server=1
 txindex=1
 datadir=/Volumes/SANDISK_64/bitcoin

#Starting bitcoin core

cd bitcoind -daemon


# Creating Miner Wallet

bitcoin-cli  createwallet Miner


# Creating Trader Wallet

bitcoin-cli  createwallet Trader


# Loading Miner Wallet

bitcoin-cli  loadwallet Miner

# Generating an address for Miner wallet with the label “Mining Reward”

bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward"

# Mining Blocks

bitcoin-cli  generatetoaddress 100 bcrt1q8fddy22r5ah7js3ukxtf4lf760qnuhc2hy348h


# Note on why wallet balance for block rewards behaves this way 

: '
In regtest mode, the mining rewards are subject to a maturity period
and require additional block confirmations, even though mining itself
is much faster and easier than in the mainnet or testnet. This is to
ensure a more realistic testing environment for developers while
allowing for rapid testing and experimentation.
'
# Checking the balance to verify it is in immature state 

bitcoin-cli  -rpcwallet=Miner getwalletinfo    


# Printing the Miner Wallet Balance

bitcoin-cli -rpcwallet=Miner getbalance

# Creating an address labeled “Received” from Trader Wallet

bitcoin-cli  -rpcwallet=Trader getnewaddress "Received"


# Printing the Miner Wallet Balance

bitcoin-cli -rpcwallet=Miner getbalance


# Sending a transaction paying 20 BTC from Miner wallet to Trader wallet


bitcoin-cli   -rpcwallet=Miner sendtoaddress bcrt1q85luer5nlnmltg6q73ksmwp3ste4janctk0ld 20

# Fetching the unconfirmed transaction

bitcoin-cli  getrawmempool true

# Confirming the transaction by creating one more block

bitcoin-cli -rpcwallet=Miner generatetoaddress 1 bcrt1q8fddy22r5ah7js3ukxtf4lf760qnuhc2hy348h


# Retrieving relevant information regarding the transaction

bitcoin-cli  -rpcwallet=Miner gettransaction b52e3b99f370273a9096010b171bba66282a520f9bb50517402579172d94fd68

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

bitcoin-cli transaction_info=$(bitcoin-cli -datadir=/Volumes/SANDISK_64/bitcoin -rpcwallet=Miner gettransaction 
b52e3b99f370273a9096010b171bba66282a520f9bb50517402579172d94fd68)

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


