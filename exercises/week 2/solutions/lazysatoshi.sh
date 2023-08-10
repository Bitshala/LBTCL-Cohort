COLOR='\033[35m'
NO_COLOR='\033[0m'

start_node() {
  echo -e "${COLOR}Starting bitcoin node...${NO_COLOR}"

  mkdir /tmp/lazysatoshi_datadir

  cat <<EOF >/tmp/lazysatoshi_datadir/bitcoin.conf
    regtest=1
    mempoolfullrbf=1
    server=1
    txindex=1

    [regtest]
    rpcuser=test
    rpcpassword=test321
    rpcbind=0.0.0.0
    rpcallowip=0.0.0.0/0
EOF

  bitcoind -regtest -datadir=/tmp/lazysatoshi_datadir -daemon
  sleep 2
}

create_wallets() {
  echo -e "${COLOR}Creating Wallets...${NO_COLOR}"

  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir createwallet Miner
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir createwallet Trader
  ADDR_MINING=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Mining Reward")
}

mining_blocks() {
  echo -e "${COLOR}Mining 103 blocks...${NO_COLOR}"

  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 103 $ADDR_MINING
}

create_parent_tx() {
  echo -e "${COLOR}Creating PARENT raw transaction...${NO_COLOR}"

  ADDR_CHANGE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getrawchangeaddress)
  ADDR_TRADER=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Trader getnewaddress "Recipient of complex raw tx from Miner")

  UTXO_TXID1=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner listunspent | jq -r '.[0] | .txid')
  UTXO_VOUT1=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner listunspent | jq -r '.[0] | .vout')
  UTXO_TXID2=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner listunspent | jq -r '.[1] | .txid')
  UTXO_VOUT2=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner listunspent | jq -r '.[1] | .vout')

  PARENT_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createrawtransaction inputs='''[ { "txid": "'$UTXO_TXID1'", "vout": '$UTXO_VOUT1', "sequence": 1 }, { "txid": "'$UTXO_TXID2'", "vout": '$UTXO_VOUT2' } ]''' outputs='''{ "'$ADDR_TRADER'": 70, "'$ADDR_CHANGE'": 29.99999 }''')
  SIGNED_PARENT_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner signrawtransactionwithwallet $PARENT_TX_RAW_HEX | jq -r '.hex')

  PARENT_TXID=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendrawtransaction $SIGNED_PARENT_TX_RAW_HEX)
  echo -e "${COLOR}Parent TXID: ${PARENT_TXID} ${NO_COLOR}"
}

fecth_parent_tx_data() {
  WEIGHT_PARENT_TX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getmempoolentry $PARENT_TXID | jq '.weight')

  # Weight Units can be converted to a "virtual size" or virtual bytes (vB) by dividing by 4 and rounding up
  VBYTES_PARENT_TX=$(echo "scale=0; $WEIGHT_PARENT_TX/4" | bc -l)

  FEE_PARENT_TX_AUX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner gettransaction $PARENT_TXID false true | jq -r '.fee')
  FEE_PARENT_TX=${FEE_PARENT_TX_AUX#-}

  OUT1_AMOUNT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner gettransaction $PARENT_TXID false true | jq -r '.decoded.vout | .[0].value')
  OUT1_SCRIPTPUB=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner gettransaction $PARENT_TXID false true | jq -r '.decoded.vout | .[0].scriptPubKey.address')
  OUT2_AMOUNT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner gettransaction $PARENT_TXID false true | jq -r '.decoded.vout | .[1].value')
  OUT2_SCRIPTPUB=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner gettransaction $PARENT_TXID false true | jq -r '.decoded.vout | .[1].scriptPubKey.address')
}

create_json() {
  echo -e "${COLOR}Creating custom JSON...${NO_COLOR}"
  JSON_DATA=$(jq --null-input \
    --arg fee_parent_tx "$FEE_PARENT_TX" \
    --arg vbytes_parent_tx "$VBYTES_PARENT_TX" \
    --arg parent_txid "$PARENT_TXID" \
    --arg out1_amount "$OUT1_AMOUNT" \
    --arg out1_scriptpub "$OUT1_SCRIPTPUB" \
    --arg out2_amount "$OUT2_AMOUNT" \
    --arg out2_scriptpub "$OUT2_SCRIPTPUB" \
    '{ "input": [
            {
            "txid": $parent_txid,
            "vout": "0"
            },
            {
            "txid": $parent_txid,
            "vout": "1"
            }
      ],
      "output": [
            {
            "script_pubkey": $out1_scriptpub,
            "amount": $out1_amount
            },
            {
            "script_pubkey": $out2_scriptpub,
            "amount": $out2_amount
            }
      ],
      "Fees": $fee_parent_tx,
      "Weight": $vbytes_parent_tx }')

  echo "$JSON_DATA"
}

create_child_tx() {
  echo -e "${COLOR}Creating CHILD raw transaction...${NO_COLOR}"

  ADDR_MINER_ADDR_CHILD=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Miner new addr for child tx")
  CHILD_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createrawtransaction inputs='''[ { "txid": "'$PARENT_TXID'", "vout": '1' } ]''' outputs='''{ "'$ADDR_MINER_ADDR_CHILD'": 29.99998 }''')
  SIGNED_CHILD_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner signrawtransactionwithwallet $CHILD_TX_RAW_HEX | jq -r '.hex')
  CHILD_TXID=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendrawtransaction $SIGNED_CHILD_TX_RAW_HEX)

  echo -e "${COLOR}Child TXID: ${CHILD_TXID} ${NO_COLOR}"

  echo -e "${COLOR}Child TX:${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getmempoolentry $CHILD_TXID
}

create_handcrafted_rbf_tx() {
  echo -e "${COLOR}Handcrafted new Parent TX bumping fee by 10k sats...${NO_COLOR}"

  RBF_PARENT_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createrawtransaction inputs='''[ { "txid": "'$UTXO_TXID1'", "vout": '$UTXO_VOUT1', "sequence": 2 }, { "txid": "'$UTXO_TXID2'", "vout": '$UTXO_VOUT2' } ]''' outputs='''{ "'$ADDR_TRADER'": 70, "'$ADDR_CHANGE'": 29.9998 }''')
  SIGNED_RBF_PARENT_TX_RAW_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner signrawtransactionwithwallet $RBF_PARENT_TX_RAW_HEX | jq -r '.hex')

  RBF_PARENT_TXID=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendrawtransaction $SIGNED_RBF_PARENT_TX_RAW_HEX)
  echo -e "${COLOR}RBF TXID: ${RBF_PARENT_TXID} ${NO_COLOR}"
}

fecth_tx_data_from_mempool() {
  echo -e "${COLOR}Child TX after bumping Parent TX with RBF:${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getmempoolentry $CHILD_TXID

  echo -e "${COLOR}RBF handcrafted TX:${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getmempoolentry $RBF_PARENT_TXID

  echo -e "${COLOR}Mempool content after broadcasting RBF TX:${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir getrawmempool
}

show_explanation() {
  echo -e "${COLOR}Explanation about what happened in the mempool:${NO_COLOR}"

  echo "After enable debug logs for mempool in bitcoind and also checking the status of the mempool using bitcoin-cli commands during the process I got the following facts"
  echo " * Once RBF tx is broadcasted child tx is removed from the mempool"
  echo " * Also parent tx is removed from the mempool"
  echo " * The only tx that remains in the mempool is the RBF handcrafted transaction"
}

clean_up() {
  echo -e "${COLOR}Clean Up${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir stop
  rm -rf /tmp/lazysatoshi_datadir
}

# Main program
start_node
create_wallets
mining_blocks
create_parent_tx
fecth_parent_tx_data
create_json
create_child_tx
create_handcrafted_rbf_tx
fecth_tx_data_from_mempool
show_explanation
clean_up
