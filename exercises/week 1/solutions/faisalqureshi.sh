

GREEN='\033[32m'
ORANGE='\033[35m'
NC='\033[0m'


#Downloading Bitcoin core, binaries and signatures

wget https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-apple-darwin.dmg
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc
wget https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS

#Verifying the binaries and signatures

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

bitcoin_data_dir="$HOME/tmp/faisal_bitcoin/"
mkdir -p "$bitcoin_data_dir"

create_conf(){
echo "regtest=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "fallbackfee=0.0001" >> "$bitcoin_data_dir/bitcoin.conf"
echo "server=1" >> "$bitcoin_data_dir/bitcoin.conf"
echo "txindex=1" >> "$bitcoin_data_dir/bitcoin.conf"

}



start_bitcoin(){
bitcoind -datadir=$bitcoin_data_dir -daemon
sleep 5
}


create_wallets(){
bitcoin-cli -datadir=$bitcoin_data_dir createwallet Miner

bitcoin-cli -datadir=$bitcoin_data_dir createwallet Trader
}


 generating_addresses(){
miner_address=$(bitcoin-cli -rpcwallet=Miner -datadir=$bitcoin_data_dir getnewaddress) 

trader_address=$(bitcoin-cli -rpcwallet=Trader -datadir=$bitcoin_data_dir getnewaddress) 
}



funding_miner(){
bitcoin-cli -rpcwallet=Miner -datadir=$bitcoin_data_dir generatetoaddress 103 $miner_address
}


send_amount(){
# sending 20 BTC from Miner wallet to Trader wallet
txid=$(bitcoin-cli   -rpcwallet=Miner -datadir=$bitcoin_data_dir sendtoaddress $trader_address 20)

}


get_mempool(){
# fetching the unconfirmed transaction
confirmed_transaction=$(bitcoin-cli  -datadir=$bitcoin_data_dir getmempoolentry $txid)
}


confirm_transaction(){
bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner generatetoaddress 1 $miner_address
}

print_info() {
    transaction_info=$(bitcoin-cli -datadir=$bitcoin_data_dir -rpcwallet=Miner gettransaction $txid)
    amount=$(echo "$transaction_info" | grep -o '"amount": -[0-9.]\+' | awk -F': ' '{print $2}' | tail -n 1)
    fee=$(echo "$confirmed_transaction" | sed -n 's/.*"base": \([0-9.]*\).*/\1/p')
    blockheight=$(echo "$transaction_info" | awk -F'"blockheight": ' '{print $2}' | awk -F, '{print $1}')

    if (( $(echo "$amount < 0" | bc -l) )); then
        amount=$(echo "scale=8; $amount * -1" | bc)
    fi

    echo "**************************************"
    echo "Transaction ID: $txid"
    echo "From Address: ${miner_address}"
    echo "To Address: ${trader_address}"
    echo "Amount: $amount"
    echo "Fee: $fee"
    echo "Block Height: $blockheight"
    echo -n "Miner Balance: $(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet="Miner" getbalance)"
    echo " | Trader Balance: $(bitcoin-cli  -datadir=$bitcoin_data_dir -rpcwallet="Trader" getbalance)"
    echo "**************************************"
}


stop_bitcoin(){
bitcoin-cli -datadir=$bitcoin_data_dir stop
}

delete_temp_directory(){
rm -rf $bitcoin_data_dir

}


create_conf
start_bitcoin
create_wallets
generating_addresses
funding_miner
send_amount
get_mempool
confirm_transaction
print_info
stop_bitcoin
delete_temp_directory



