#!/bin/bash
# Expand aliases for alias to work in script
shopt -s expand_aliases
# Setting alias to make script easier to read
alias btc-cli='bitcoin-cli -regtest -datadir=/tmp/josei '


start_node() {
  echo -e "${COLOR}Starting bitcoin node...${NO_COLOR}"

  mkdir -p /tmp/josei

  cat <<EOF >/tmp/josei/bitcoin.conf
    regtest=1
    fallbackfee=0.00001
    server=1
    txindex=1

EOF

  bitcoind -regtest -datadir=/tmp/josei -daemon
  sleep 2
}


create_wallet() {
    btc-cli -named createwallet wallet_name=$1 descriptors=false
}


# Get new address for chosen wallet an label it with wallet's name
get_new_address() {
    btc-cli -rpcwallet="$1" getnewaddress "$1 address"
    exit
}

# First parameter: number of blocks to generate
# Second parameter: address to generate to
generate_to_address() {
    btc-cli generatetoaddress $1 $2 > /dev/null
}


fund_wallets() {
    miner_address=$(get_new_address "Miner")
    employer_address=$(get_new_address "Employer")
    
    generate_to_address 101 $miner_address > /dev/null

    # Keeping this TX ID to spend it later on
    employer_TX_ID=$(btc-cli -rpcwallet=Miner sendtoaddress $employer_address 45)

    generate_to_address 1 $miner_address > /dev/null
}


create_employer_transaction() {
    employee_address=$(get_new_address "Employee")
    employer_change_address=$(get_new_address "Employer")
    employer_Vout=$(btc-cli -rpcwallet=Employer listunspent |jq -r '.[0]|.vout')

    payment_TX_HEX=$(btc-cli -named createrawtransaction inputs='''[ { "txid": "'$employer_TX_ID'", "vout": '$employer_Vout' } ]''' outputs='''{ "'$employee_address'": 40, "'$employer_change_address'": 4.9999 }''' locktime=500)
    signed_payment_TX=$(btc-cli -rpcwallet=Employer signrawtransactionwithwallet $payment_TX_HEX | jq -r '.hex')
}


create_employee_transaction() {
    new_employee_address=$(get_new_address "Employee")
    employee_TX_ID=$(btc-cli -rpcwallet=Employee listunspent |jq -r '.[0]|.txid')
    employee_Vout=$(btc-cli -rpcwallet=Employee listunspent |jq -r '.[0]|.vout')
    
    # Hashing data in order to obtain only HEX characters
    op_return_data=$(echo "I got my salary, I am rich"| sha256sum | awk '{print $1}')
    echo "Hash 256 of \"I got my salary, I am rich\" "
    echo $op_return_data
    echo " "
    auto_TX_HEX=$(btc-cli -named createrawtransaction inputs='''[ { "txid": "'$employee_TX_ID'", "vout": '$employee_Vout' } ]''' outputs='''{ "data": "'$op_return_data'", "'$new_employee_address'": 39.99995 }''')
    signed_auto_TX=$(btc-cli -rpcwallet=Employee signrawtransactionwithwallet $auto_TX_HEX | jq -r '.hex')
    auto_TX_ID=$(btc-cli -rpcwallet=Employee sendrawtransaction $signed_auto_TX)
    generate_to_address 1 $miner_address > /dev/null

    echo "Verifying hash is in transaction: "
    op_data_TX_ID=$(btc-cli -rpcwallet=Employee listunspent|jq -r '.[0]|.txid')
    op_data_RAW_TX=$(btc-cli getrawtransaction $op_data_TX_ID)
    btc-cli decoderawtransaction $op_data_RAW_TX|grep $op_return_data
}


print_balances(){
    echo "Employer final balance:"
    btc-cli -rpcwallet=Employer getbalance
    echo "Employee final balance:"
    btc-cli -rpcwallet=Employee getbalance
}


clean_up() {
  echo -e "${COLOR}Clean Up${NO_COLOR}"
  btc-cli stop
  rm -rf /tmp/josei
}

# Main program
start_node

echo " "
echo "---------------------------------------------------------------------------------------------------------------------------------"
echo "----------------------------------------------------Setup a TimeLock contract----------------------------------------------------"
echo "---------------------------------------------------------------------------------------------------------------------------------"
echo " "

echo "-----Create three wallets: Miner, Employee, and Employer. -----------------------------------------------------------------------"
create_wallet "Miner"
create_wallet "Employer"
create_wallet "Employee"
echo "---------------------------------------------------------------------------------------------------------------------------------"


echo " "
echo "-----Fund the wallets by generating some blocks for Miner and sending some coins to Employer. -----------------------------------"
fund_wallets
echo "---------------------------------------------------------------------------------------------------------------------------------"


echo " "
echo "----- Create a salary transaction of 40 BTC, where the Employer pays the Employee. ----------------------------------------------"
echo "----- Add an absolute timelock of 500 Blocks for the transaction, ---------------------------------------------------------------"
echo "----- i.e. the transaction cannot be included in the blockchain until the 500th block is mined. ---------------------------------"
create_employer_transaction
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "----- Report in a comment what happens when you try to broadcast this transaction. ----------------------------------------------"
echo "As we are about to verify, sending the transaction will fail with a \"non-final\" message, as the blockchain has not reached 500 blocks yet: "
payment_TX_ID=$(btc-cli -rpcwallet=Employer sendrawtransaction $signed_payment_TX)
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "----- Mine up to 500th block and broadcast the transaction. ---------------------------------------------------------------------"
generate_to_address 400 $miner_address > /dev/null
payment_TX_ID=$(btc-cli -rpcwallet=Employer sendrawtransaction $signed_payment_TX)
generate_to_address 1 $miner_address > /dev/null
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "---------- Print the final balances of the Employee and Employer. ---------------------------------------------------------------"
print_balances
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "---------------------------------------------------------------------------------------------------------------------------------"
echo "----------------------------------------------- Spend from the TimeLock ---------------------------------------------------------"
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "---------- Create a spending transaction where the Employee spends the fund to a new Employee wallet address. -------------------"
echo "---------- Add an OP_RETURN output in the spending transaction with the string data "I got my salary, I am rich". ----------------"
echo "---------- Extract and broadcast the fully signed transaction. ------------------------------------------------------------------"
create_employee_transaction
echo "---------------------------------------------------------------------------------------------------------------------------------"

echo " "
echo "---------- Print the final balances of the Employee and Employer. ---------------------------------------------------------------"
print_balances
echo "---------------------------------------------------------------------------------------------------------------------------------"

clean_up
exit
