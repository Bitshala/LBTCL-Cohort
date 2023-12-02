COLOR='\033[35m'
NO_COLOR='\033[0m'

# Create a bitcoind config file and start the bitcoin node.
start_node() {
  echo -e "${COLOR}Starting bitcoin node...${NO_COLOR}"

  mkdir /tmp/lazysatoshi_datadir

  cat <<EOF >/tmp/lazysatoshi_datadir/bitcoin.conf
    regtest=1
    fallbackfee=0.00001
    server=1
    txindex=1

    [regtest]
    rpcuser=test
    rpcpassword=test321
    rpcbind=0.0.0.0
    rpcallowip=0.0.0.0/0
EOF

  bitcoind -datadir=/tmp/lazysatoshi_datadir -daemon
  sleep 2
}

# Create wallets: Miner and Alice.
create_wallets() {
  echo -e "${COLOR}Creating Wallets...${NO_COLOR}"
  # Legacy wallets created in order to use command dumpprivkey
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Miner descriptors=false
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Alice descriptors=false
  ADDR_MINING=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Mining Reward")
  ADDR_MINER=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Miner receive Alice payment" legacy)
  PUBKEY_ADDR_MINER=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner -named getaddressinfo address=$ADDR_MINER | jq -r '.pubkey')
}

# Mining some blocks to be able to spend mined coins
mining_blocks() {
  echo -e "${COLOR}Mining 103 blocks...${NO_COLOR}"

  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 103 $ADDR_MINING >/dev/null
}

# Funding wallets and generate required addresses for the exercise
funding_wallets() {
  echo -e "${COLOR}Funding Alice wallet...${NO_COLOR}"

  ADDR_ALICE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getnewaddress "Funding wallet")
  ADDR_SPENT=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getnewaddress "Receiving spended CSV")
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendtoaddress $ADDR_ALICE 80
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING >/dev/null
}

# Create a transaction where Alice pays 10 BTC back to Miner, but with a relative timelock of 10 blocks.
create_csv_transaction() {
  echo -e "${COLOR}Creating CSV Transaction...${NO_COLOR}"
  UTXO_TXID_ALICE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent | jq -r '.[] | .txid')
  UTXO_VOUT_ALICE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent | jq -r '.[] | .vout')
  ADDR_ALICE_CHANGE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getrawchangeaddress)

  # Bitcoin script for CSV
  # <10 blocks> OP_CHECKSEQUENCEVERIFY OP_DROP OP_DUP OP_HASH160 <pubKeyHash> OP_EQUALVERIFY OP_CHECKSIG
  # CSV 10 blocks convert to LE encoded with 3 bytes
  # LE Hex: 0a
  # Though that should be padded out to 00000a, requiring a code of 0300000a.
  BLOCKS_LE_ENCODED="0300000a" # this value was computed using integer2lehex.sh and some manual stuff

  # Creating bitcoin script hex using btcc
  SCRIPT_HEX=$(btcc $BLOCKS_LE_ENCODED OP_CHECKSEQUENCEVERIFY OP_DROP OP_DUP OP_HASH160 $PUBKEY_ADDR_MINER OP_EQUALVERIFY OP_CHECKSIG)

  echo -e "${COLOR}Script Hex CSV Transaction: ${SCRIPT_HEX} ${NO_COLOR}"

  echo -e "${COLOR}Decoded Script CSV Transaction: ${NO_COLOR}"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir decodescript $SCRIPT_HEX

  P2SH_ADDR=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir decodescript $SCRIPT_HEX | jq -r '.p2sh')
  echo "P2SH: ${P2SH_ADDR}"

  CSV_LOCKED_TXID=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice sendtoaddress $P2SH_ADDR 10)

  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING >/dev/null
}

# Report in a comment what happens when you try to broadcast this transaction.
show_explanation() {
  echo -e "${COLOR} Blab albal ${NO_COLOR}"
  echo ""
}

mining_10_blocks() {
  echo -e "${COLOR}Mining 10 blocks...${NO_COLOR}"

  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 10 $ADDR_MINING >/dev/null
}

spending_csv_transaction() {

  # In order to spent CSV Miner sould create a tx and signing it. But it is not as easy as it seems.
  # UTXO it is locked to an P2SH address. If we list unspent utxos for miner wallet, utxo locked with csv  not appears

  # We can import p2sh  address using bitcoin-cli importaddress command, but I could not be able to spent easly, only to track it

  # After doing some research I think that the way to spent it will be:

  # extract the privkeys of the publickey used to receive CSV tx
  PRIVKEY_ADDR_MINER=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner -named dumpprivkey address=$ADDR_MINER)

  echo "Transaction data $CSV_LOCKED_TXID:"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice gettransaction $CSV_LOCKED_TXID false true
  CSV_VOUT=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice gettransaction $CSV_LOCKED_TXID false true | jq -r '.details | .[0].vout')

  # create the spent transaction
  SPENT_CSV_TX_RAW_HEX=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createrawtransaction inputs='''[ { "txid": "'$CSV_LOCKED_TXID'", "vout": '$CSV_VOUT', "sequence": 10 } ]''' outputs='''{ "'$ADDR_SPENT'": 9.99998 }''')

  # get the scriptpubkey jq --arg keyvar "$bash_var" '.[$keyvar]' json
  SCRIPT_PUBKEY=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice gettransaction $CSV_LOCKED_TXID false true | jq --argjson csvout ${CSV_VOUT}  -r '.decoded.vout | .[$csvout].scriptPubKey.hex')
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice gettransaction $CSV_LOCKED_TXID false true | jq --argjson csvout 1 -r '.decoded.vout | .[$csvout].scriptPubKey.hex'

  # sign the transaction using signrawtransactionwithkey and passing the redeem script used to lock the funds
  # Useful info https://github.com/BlockchainCommons/Learning-Bitcoin-from-the-Command-Line/blob/master/06_2_Spending_a_Transaction_to_a_Multisig.md
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner -named signrawtransactionwithkey hexstring=$SPENT_CSV_TX_RAW_HEX prevtxs='''[ { "txid": "'$CSV_LOCKED_TXID'", "vout": '$CSV_VOUT', "scriptPubKey": "'$SCRIPT_PUBKEY'", "redeemScript": "'$SCRIPT_HEX'" } ]''' privkeys='["'$PRIVKEY_ADDR_MINER'"]'
  #echo "-----hexstring=$SPENT_CSV_TX_RAW_HEX prevtxs=--$CSV_LOCKED_TXID--$SCRIPT_PUBKEY---$SCRIPT_HEX---$PRIVKEY_ADDR_MINER---"
}

# Disclaimer
disclaimer_message() {
  echo -e "${COLOR} ------------------------------------------------------------------------------ ${NO_COLOR}"
  echo -e "${COLOR} ----  SCRIPT IS NOT WORKING PROPERLY --------- ${NO_COLOR}"
  echo "I  tried, without success, to make the assignment using Bitcoin scripting and using OP_CODE OP_CHECKSEQUENCEVERIFY. But I was not able to spent de CSV locked UTXO. I got the error"
  echo -e "${COLOR} ----  Unable to sign input, invalid stack size (possibly missing key) ------ ${NO_COLOR}"
  echo " when I try to sign the spending transaction. Despite having failed, I have learned a lot during the journey."
  echo -e "${COLOR} ------------------------------------------------------------------------------ ${NO_COLOR}"
}


# Print the final balance of Miner and Alice.
printing_alice_wallet_balance() {
  echo -e "${COLOR}Alice wallet balance:${NO_COLOR}"

  echo "Alice Wallet:"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent

  echo "Miner Wallet:"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner listunspent
}

clean_up() {
  echo -e "${COLOR}Clean Up${NO_COLOR}"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir stop
  rm -rf /tmp/lazysatoshi_datadir
}

# Main program
disclaimer_message 
start_node
create_wallets
mining_blocks
funding_wallets
printing_alice_wallet_balance
create_csv_transaction
printing_alice_wallet_balance
mining_10_blocks
spending_csv_transaction
clean_up
disclaimer_message
