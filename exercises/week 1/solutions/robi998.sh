download_binaries(){
  bitcoin_core_url="https://bitcoincore.org/bin/bitcoin-core-25.0/bitcoin-25.0-x86_64-linux-gnu.tar.gz"
  bitcoin_core_tar="bitcoin-25.0-x86_64-linux-gnu.tar.gz"
  bitcoin_checksum_url="https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS"
  bitcoin_checksum_file="SHA256SUMS"
  bitcoin_signature_url="https://bitcoincore.org/bin/bitcoin-core-25.0/SHA256SUMS.asc"
  bitcoin_signature_file="SHA256SUMS.asc"
  wget "$bitcoin_core_url" -O "$bitcoin_core_tar"
  wget "$bitcoin_checksum_url" -O "$bitcoin_checksum_file"
  wget "$bitcoin_signature_url" -O "$bitcoin_signature_file"
}

verify_hash(){
  hash_verification_result=$(sha256sum --ignore-missing --check SHA256SUMS)
  if echo "$hash_verification_result" | grep -q "OK$"; then
    echo "Hash verification successful."
  else
    echo "Hash verification failed."
    exit 1
  fi
}

verify_signature(){
  git clone https://github.com/bitcoin-core/guix.sigs
  gpg --import guix.sigs/builder-keys/*
  gpg --verify SHA256SUMS.asc
  if [ $? -eq 0 ]; then
     echo "Binary signature verification successful."
  else
     echo "Binary signature verification failed."
     exit 1
  fi
}

extract_and_copy_binaries(){
  tar -xvf "$bitcoin_core_tar"
  sudo cp bitcoin-25.0/bin/* /usr/local/bin/
  sudo chmod +x /usr/local/bin/bitcoin*
}

create_conf_file(){
  mkdir -p /home/$(whoami)/.bitcoin/
  echo "regtest=1" > /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "fallbackfee=0.0001" >> /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "server=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "txindex=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
}

start_bitcoind(){
  bitcoind -daemon
  sleep 10
}

create_miner_wallet(){
  bitcoin-cli createwallet Miner
  miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")
}

mine_blocks_untill_positive_balance(){
  balance=0
  blocks=0
  while (( $(echo "$balance <= 0" | bc -l) )); do
      bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "$miner_address"
      balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
      blocks=$((blocks + 1))
  done
}

print_miner_balance(){
  miner_balance=$(bitcoin-cli -rpcwallet=Miner getbalance)
  echo "Miner Wallet Balance: $miner_balance BTC"
  echo "Number of blocks mined: $blocks"
}

create_trader_wallet(){
  bitcoin-cli createwallet Trader
  trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Received")
}

send_transaction(){
  bitcoin-cli -rpcwallet=Miner sendtoaddress "$trader_address" 20
}

fetch_unconfirmed_transaction(){
  sudo apt-get install jq
  unconfirmed_txs=$(bitcoin-cli getrawmempool)
  unconfirmed_tx=$(echo "$unconfirmed_txs" | jq -r '.[0]')
  bitcoin-cli getmempoolentry "$unconfirmed_tx"
}

confirm_transaction(){
  bitcoin-cli -rpcwallet=Miner generatetoaddress 1 "$miner_address"
}

fetch_transaction_details() {
  details=$(bitcoin-cli -rpcwallet=Miner gettransaction "$unconfirmed_tx")
  miner_balance_after_tx=$(bitcoin-cli -rpcwallet=Miner getbalance)
  trader_balance_after_tx=$(bitcoin-cli -rpcwallet=Trader getbalance)
  echo "txid: $(jq '.txid' <<< $details)"
  echo "From, Amount: $miner_address, $(jq '.amount' <<< $details)"
  echo "Send, Amount: $trader_address, 20"
  echo "Change, Amount: $miner_address, $(jq '.amount' <<< $details)"
  echo "Fees: $(jq '.fee' <<< $details)"
  echo "Block: $(jq '.blockheight' <<< $details)"
  echo "Miner Balance: $miner_balance_after_tx BTC"
  echo "Trader Balance: $trader_balance_after_tx BTC"
}

#setup
download_binaries
verify_hash
verify_signature
extract_and_copy_binaries

#initiate
create_conf_file
start_bitcoind
create_miner_wallet
mine_blocks_untill_positive_balance
print_miner_balance

#usage
create_trader_wallet
send_transaction
fetch_unconfirmed_transaction
confirm_transaction
fetch_transaction_details
