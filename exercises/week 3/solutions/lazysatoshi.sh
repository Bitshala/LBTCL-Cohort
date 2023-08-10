COLOR='\033[35m'
NO_COLOR='\033[0m'

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

  bitcoind -regtest -datadir=/tmp/lazysatoshi_datadir -daemon
  sleep 2
}

create_wallets() {
  echo -e "${COLOR}Creating Wallets...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Miner descriptors=false
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Alice descriptors=false
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Bob descriptors=false
  ADDR_MINING=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Mining Reward" legacy)
}

mining_blocks() {
  echo -e "${COLOR}Mining 103 blocks...${NO_COLOR}"

  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 103 $ADDR_MINING
}

funding_wallets() {
  echo -e "${COLOR}Funding wallets...${NO_COLOR}"

  ADDR_BOB=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob getnewaddress "Funding wallet" legacy)
  ADDR_ALICE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getnewaddress "Funding wallet" legacy)
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendtoaddress $ADDR_BOB 40
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendtoaddress $ADDR_ALICE 40
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING
}

create_multisig_addr() {
  echo -e "${COLOR}Generating multisig address...${NO_COLOR}"

  ADDR_BOB_MULTISIG=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob getnewaddress legacy)
  ADDR_ALICE_MULTISIG=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getnewaddress legacy)
  PUBKEY_BOB_MULTISIG=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named getaddressinfo address=$ADDR_BOB_MULTISIG | jq -r '.pubkey')
  PUBKEY_ALICE_MULTISIG=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice -named getaddressinfo address=$ADDR_ALICE_MULTISIG | jq -r '.pubkey')

  ADDR_MULTISIG=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named createmultisig nrequired=2 keys='''["'$PUBKEY_BOB_MULTISIG'","'$PUBKEY_ALICE_MULTISIG'"]''' | jq -r '.address')
}

create_psbt(){
  echo -e "${COLOR}Creating Partial Signed Bitcoin Transaction...${NO_COLOR}"

  UTXO_TXID_BOB=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob listunspent | jq -r '.[] | .txid' )
  UTXO_VOUT_BOB=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob listunspent | jq -r '.[] | .vout' )
  UTXO_TXID_ALICE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent | jq -r '.[] | .txid' )
  UTXO_VOUT_ALICE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent | jq -r '.[] | .vout' )
  ADDR_BOB_CHANGE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob getrawchangeaddress legacy)
  ADDR_ALICE_CHANGE=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getrawchangeaddress legacy)
  PSBT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named createpsbt inputs='''[ { "txid": "'$UTXO_TXID_BOB'", "vout": '$UTXO_VOUT_BOB' }, { "txid": "'$UTXO_TXID_ALICE'", "vout": '$UTXO_VOUT_ALICE' } ]''' outputs='''[{ "'$ADDR_MULTISIG'": 20 },{ "'$ADDR_BOB_CHANGE'": 29.99998 } ,{ "'$ADDR_ALICE_CHANGE'": 29.99998 }]''')

  echo -e "${COLOR}Details of Partial Signed Bitcoin Transaction...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  decodepsbt psbt=$PSBT
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  analyzepsbt psbt=$PSBT
  PSBT_BOB_RAW=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob walletprocesspsbt $PSBT | jq -r '.psbt')

  echo -e "${COLOR}Details of Partial Signed Bitcoin Transaction after Bob processed...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  analyzepsbt psbt=$PSBT_BOB_RAW
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  decodepsbt psbt=$PSBT_BOB_RAW
  PSBT_ALICE_RAW=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice walletprocesspsbt $PSBT_BOB_RAW | jq -r '.psbt')

  echo -e "${COLOR}Details of Partial Signed Bitcoin Transaction after Alice processed...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  analyzepsbt psbt=$PSBT_ALICE_RAW
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  decodepsbt psbt=$PSBT_ALICE_RAW
  PSBT_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  finalizepsbt  psbt=$PSBT_ALICE_RAW | jq -r '.hex')

  echo -e "${COLOR}Details of Partial Signed Bitcoin Transaction after finalized...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob decoderawtransaction $PSBT_HEX

  echo -e "${COLOR}Broadcasting PSBT to Bitcoin network...${NO_COLOR}"
  TXID_PSBT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named sendrawtransaction hexstring=$PSBT_HEX)

  echo -e "${COLOR}Mempool content:${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir  getmempoolinfo
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING
}

printing_wallet_balances() {
  echo -e "${COLOR}Wallets balances:${NO_COLOR}"

  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice listunspent
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob listunspent
}

create_spending_psbt() {
  echo -e "${COLOR}Importing Multisig Address to Bob and Alice Wallets...${NO_COLOR}"
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob  -named addmultisigaddress  nrequired=2 keys='''["'$PUBKEY_BOB_MULTISIG'","'$PUBKEY_ALICE_MULTISIG'"]'''
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice  -named addmultisigaddress  nrequired=2 keys='''["'$PUBKEY_BOB_MULTISIG'","'$PUBKEY_ALICE_MULTISIG'"]'''

  echo -e "${COLOR}Creating Spending PSBT...${NO_COLOR}"
  ADDR_MULTISIG_BOB_PAYMENT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob getnewaddress legacy)
  ADDR_MULTISIG_ALICE_PAYMENT=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice getnewaddress legacy )
  PSBT_SPEND=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named createpsbt inputs='''[ { "txid": "'$TXID_PSBT'", "vout": 0 } ]''' outputs='''[{ "'$ADDR_MULTISIG_BOB_PAYMENT'": 9.999998 },{ "'$ADDR_MULTISIG_ALICE_PAYMENT'": 9.99998 }]''')
  echo "Control"
  PSBT_SPEND_BOB_RAW=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob walletprocesspsbt $PSBT_SPEND | jq -r '.psbt')
  PSBT_SPEND_ALICE_RAW=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Alice walletprocesspsbt $PSBT_SPEND_BOB_RAW | jq -r '.psbt')
  PSBT_SPEND_HEX=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named  finalizepsbt  psbt=$PSBT_SPEND_ALICE_RAW | jq -r '.hex')
  TXID_PSBT_SPEND=$(bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Bob -named sendrawtransaction hexstring=$PSBT_SPEND_HEX)
  bitcoin-cli -regtest -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING
}

show_explanation() {
  echo -e "${COLOR}Disclamer: Final balances of Alice and Bob. Alice should be around 3 BTC poorer, and Bob 3 BTC richer.${NO_COLOR}"
  echo "According to problem statement final balances of Alice and Bob. Alice should be around 3 BTC poorer than Bob. I can understand why. In my implementation Alice and Bob share fee expenses, maybe this is key point."  

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
funding_wallets
create_multisig_addr
create_psbt
printing_wallet_balances
create_spending_psbt
printing_wallet_balances
show_explanation
clean_up
