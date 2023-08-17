setup_node(){
  BITCOIN_PATH="/usr/local/bin/" #modify the path if necessary
  mkdir -p /home/$(whoami)/.bitcoin/
  echo "regtest=1" > /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "fallbackfee=0.0001" >> /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "server=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
  echo "txindex=1" >> /home/$(whoami)/.bitcoin/bitcoin.conf
  sudo apt-get install jq > /dev/null 2>&1
  ${BITCOIN_PATH}bitcoind -daemon
  sleep 10
}

create_and_fund_wallet(){
  bitcoin-cli createwallet Miner > /dev/null 2>&1
  bitcoin-cli createwallet Trader > /dev/null 2>&1
  bitcoin-cli loadwallet Miner > /dev/null 2>&1
  bitcoin-cli loadwallet Trader > /dev/null 2>&1
  miner_address=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner getnewaddress)
  ${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner generatetoaddress 103 $miner_address > /dev/null 2>&1
  miner_balance=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner getbalance)
}
craft_parent_transaction(){
  utxo_txid_1=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0].txid')
  utxo_txid_2=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[1].txid')
  utxo_vout_1=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[0].vout')
  utxo_vout_2=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner listunspent | jq -r '.[1].vout')
  changeaddress=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner getrawchangeaddress)
  trader_address=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Trader getnewaddress)
  rawparenttx=$(${BITCOIN_PATH}bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1' }, { "txid": "'$utxo_txid_2'", "vout": '$utxo_vout_2' } ]'''       outputs='''{ "'$trader_address'": 70, "'$changeaddress'": 29.99999 }''')
}
sign_and_broadcast_parent_tx(){
  signedparenttx=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$rawparenttx | jq -r '.hex')
  txid_parent=$(${BITCOIN_PATH}bitcoin-cli -named sendrawtransaction hexstring=$signedparenttx)
}
get_parent_tx_details(){
  tx_details=$(${BITCOIN_PATH}bitcoin-cli getmempoolentry "$txid_parent")
  fees=$(echo "$tx_details" | jq -r '.fees.base')
  weight=$(echo "$tx_details" | jq -r '.weight')
  
  JSON_VARIABLE='''{
  "input": [
    {
      "txid": "'$utxo_txid_1'",
      "vout": '$utxo_vout_1'
    },
    {
      "txid": "'$utxo_txid_2'",
      "vout": '$utxo_vout_2'
    }
  ],
  "output": [
    {
      "script_pubkey": "'$(bitcoin-cli -rpcwallet=Miner getaddressinfo "$miner_address" | jq -r '.scriptPubKey')'",
      "amount": '$miner_balance'
    },
    {
      "script_pubkey": "'$(bitcoin-cli -rpcwallet=Trader getaddressinfo "$trader_address" | jq -r '.scriptPubKey')'",
      "amount": 70
    }
  ],
  "Fees": '$fees',
  "Weight": '$weight'
  }'''
  echo $JSON_VARIABLE
}
create_and_broadcast_child_tx(){
  miner_address_new=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner getnewaddress)
  rawchildtx=$(${BITCOIN_PATH}bitcoin-cli -named createrawtransaction inputs='''[{ "txid": "'$txid_parent'", "vout": '1' }]'''  outputs='''{ "'$miner_address_new'":   29.99998 }''')
  signedchildtx=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$rawchildtx | jq -r '.hex')
  txid_child=$(${BITCOIN_PATH}bitcoin-cli -named sendrawtransaction hexstring=$signedchildtx)
}
query_child_tx(){
  echo -e "child transaction before bumping parent transaction is:"
  ${BITCOIN_PATH}bitcoin-cli getmempoolentry "$txid_child"
}
bump_parent_tx_and_broadcast(){
  rbfrawparenttx=$(${BITCOIN_PATH}bitcoin-cli -named createrawtransaction inputs='''[ { "txid": "'$utxo_txid_1'", "vout": '$utxo_vout_1', "sequence":2 }, { "txid": "'$utxo_txid_2'", "vout": '$utxo_vout_2' } ]'''   outputs='''{ "'$trader_address'": 70, "'$changeaddress'": 29.99989 }''')
  rbfsignedparenttx=$(${BITCOIN_PATH}bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$rbfrawparenttx | jq -r '.hex')
  rbf_txid_parent=$(${BITCOIN_PATH}bitcoin-cli -named sendrawtransaction hexstring=$rbfsignedparenttx)
}
query_child_tx_and_explain(){
  echo -e "child transaction after bumping parent transaction is:"
  ${BITCOIN_PATH}bitcoin-cli getmempoolentry "$txid_child"
  echo -e "the new rbf transaction is replacing the old one in mempool.since the child transaction is created using the old parent transaction(which got replaced),the child tx becomes invalid" 
}
clean_up(){
 ${BITCOIN_PATH}bitcoin-cli stop
}


setup_node
create_and_fund_wallet
craft_parent_transaction
sign_and_broadcast_parent_tx
get_parent_tx_details
create_and_broadcast_child_tx
query_child_tx
bump_parent_tx_and_broadcast
query_child_tx_and_explain
clean_up
