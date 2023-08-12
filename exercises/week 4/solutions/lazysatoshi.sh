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

# Create three wallets: Miner, Employee, and Employer.
create_wallets() {
  echo -e "${COLOR}Creating Wallets...${NO_COLOR}"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Miner
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Employee
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createwallet wallet_name=Employer
  ADDR_MINING=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner getnewaddress "Mining Reward")
}

# Mining some blocks to be able to spend mined coins
mining_blocks() {
  echo -e "${COLOR}Mining 103 blocks...${NO_COLOR}"

  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 103 $ADDR_MINING > /dev/null
}

# Funding wallets and generate required addresses for the exercise
funding_wallets() {
  echo -e "${COLOR}Funding Employer wallet...${NO_COLOR}"

  ADDR_EMPLOYER=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer getnewaddress "Funding wallet")
  ADDR_EMPLOYEE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee getnewaddress "Receiving salary address")
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner sendtoaddress $ADDR_EMPLOYER 80
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING > /dev/null
}

# Create a salary transaction of 40 BTC, where the Employer pays the Employee.
create_salary_transaction(){
  echo -e "${COLOR}Creating Salary Transaction...${NO_COLOR}"

  UTXO_TXID_EMPLOYER=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer listunspent | jq -r '.[] | .txid' )
  UTXO_VOUT_EMPLOYER=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer listunspent | jq -r '.[] | .vout' )
  ADDR_EMPLOYER_CHANGE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer getrawchangeaddress)
  SALARY_TX_RAW_HEX=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer -named createrawtransaction inputs='''[ { "txid": "'$UTXO_TXID_EMPLOYER'", "vout": '$UTXO_VOUT_EMPLOYER' } ]''' outputs='''{ "'$ADDR_EMPLOYEE'": 40, "'$ADDR_EMPLOYER_CHANGE'": 39.99995 }''' locktime=500)

  echo "SALARY RAW TX HEX: $SALARY_TX_RAW_HEX"
  SIGNED_SALARY_TX_RAW_HEX=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer signrawtransactionwithwallet $SALARY_TX_RAW_HEX | jq -r '.hex')
  SALARY_TXID=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer sendrawtransaction $SIGNED_SALARY_TX_RAW_HEX)
}

# Report in a comment what happens when you try to broadcast this transaction.
show_explanation() {
  echo -e "${COLOR}Got above error when broadcasting tx with locktime=500. Block 500 is not reached ${NO_COLOR}"
  echo ""
}

# Mine up to 500th block and broadcast the transaction.
mining_until_500_blocks() {
  echo -e "${COLOR}Mining blocks...${NO_COLOR}"

  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 396 $ADDR_MINING > /dev/null
  echo -e "${COLOR}Block 500 created...${NO_COLOR}"
  SALARY_TXID=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer sendrawtransaction $SIGNED_SALARY_TX_RAW_HEX)
  echo -e "Broadcasting again salary transaction: $SALARY_TXID"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING > /dev/null
}

# Print the final balances of Employee and Employer.
printing_wallet_balances() {
  echo -e "${COLOR}Wallets balances after salary transaction is processed:${NO_COLOR}"

  echo "Employee Wallet:"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee listunspent
  echo "Employer Wallet:"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer listunspent
}

# Create a spending transaction where the Employee spends the fund to a new Employee wallet address.
# Add an OP_RETURN output in the spending transaction with the string data "I got my salary, I am rich".
create_op_return_tx() {
  echo -e "${COLOR}Creating OP_RETURN transaction...${NO_COLOR}"

  # Create required variables
  UTXO_TXID_EMPLOYEE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee listunspent | jq -r '.[] | .txid' )
  UTXO_VOUT_EMPLOYEE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee listunspent | jq -r '.[] | .vout' )
  ADDR_EMPLOYEE_CHANGE=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee getrawchangeaddress)
  OP_RETURN_DATA="I got my salary, I am rich"
  OP_RETURN_DATA="abcde131ad"

  # Create transaction
  OP_RETURN_TX_RAW_HEX=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -named createrawtransaction inputs='''[ { "txid": "'$UTXO_TXID_EMPLOYEE'", "vout": '$UTXO_VOUT_EMPLOYEE' } ]''' outputs='''{ "data": "'$OP_RETURN_DATA'", "'$ADDR_EMPLOYEE_CHANGE'": 39.99998 }''')
  echo "OP RETURN RAW TX HEX: $OP_RETURN_TX_RAW_HEX"

  # Sign transaction
  SIGNED_OP_RETURN_TX_RAW_HEX=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employee signrawtransactionwithwallet $OP_RETURN_TX_RAW_HEX | jq -r '.hex')

  # Broadcast transaction
  OP_RETURN_TXID=$(bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Employer sendrawtransaction $SIGNED_OP_RETURN_TX_RAW_HEX)

  # Mine a block to write OP_RETURN into blockchain
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir -rpcwallet=Miner generatetoaddress 1 $ADDR_MINING > /dev/null
}

clean_up() {
  echo -e "${COLOR}Clean Up${NO_COLOR}"
  bitcoin-cli -datadir=/tmp/lazysatoshi_datadir stop
  rm -rf /tmp/lazysatoshi_datadir
}

# Main program
start_node
create_wallets
mining_blocks
funding_wallets
create_salary_transaction
show_explanation
mining_until_500_blocks
printing_wallet_balances
create_op_return_tx
printing_wallet_balances
clean_up
