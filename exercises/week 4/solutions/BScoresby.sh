#!/bin/bash

setup(){
    mkdir -p /home/$USER/.bitcoin/tmp;
    touch /home/$USER/.bitcoin/tmp/bitcoin.conf
    echo "regtest=1  
	fallbackfee=0.0001
        server=1
        txindex=1
        daemon=1" >> /home/$USER/.bitcoin/tmp/bitcoin.conf
    BITCOINCLI="/usr/local/bin/bitcoin/bin/bitcoin-cli"
    DATADIR="-datadir=/home/$USER/.bitcoin/tmp"
}

install_jq(){
    if ! command -v jq &> /dev/null
    then
        sudo apt-get install jq
    fi
}

start_bitcoind(){
    /usr/local/bin/bitcoin/bin/bitcoind $DATADIR -daemon
    sleep 3
}

create_wallet(){
    $BITCOINCLI $DATADIR -named createwallet wallet_name="$1" disable_private_keys="$2" blank="$3" 1> /dev/null
}

create_address(){
    $BITCOINCLI $DATADIR -rpcwallet=$1 getnewaddress
}

mine_new_blocks(){
    MINER1=`create_address $1`
    $BITCOINCLI $DATADIR generatetoaddress $2 "$MINER1" > /dev/null
}

send_coins(){
    $BITCOINCLI $DATADIR -rpcwallet=$1 -named sendtoaddress address="$2" amount="$3" fee_rate=25 
}

get_balance(){
    $BITCOINCLI $DATADIR -named -rpcwallet=$1 getbalance
}

create_transaction(){
    SENDERTXID=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .txid'))
    SENDERVOUT=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .vout'))
    
    UTXO1_TXID=${SENDERTXID[0]}
    UTXO1_VOUT=${SENDERVOUT[0]}
    RECEIVER_ADDR=$(create_address $2)
    CHANGE_ADDR=$($BITCOINCLI $DATADIR -rpcwallet=$1 getrawchangeaddress)

    HEX=$($BITCOINCLI $DATADIR -rpcwallet=$1 -named createrawtransaction inputs='''[{"txid": "'$UTXO1_TXID'", "vout": '$UTXO1_VOUT' }]''' outputs='''{"'$RECEIVER_ADDR'": 40.0, "'$CHANGE_ADDR'": 9.9998 }''' locktime=500)   
}

sign_transaction(){
    unset signedtx
    signedtx=$($BITCOINCLI $DATADIR -rpcwallet=$1 -named signrawtransactionwithwallet hexstring=$2 | jq -r '.hex')
    echo "Signing transaction..."
}

send_transaction(){
    $BITCOINCLI $DATADIR -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtx > /dev/null
    echo "Broadcasting transaction..."
}

create_opreturn(){
    SENDERTXID=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .txid'))
    SENDERVOUT=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .vout'))
    
    UTXO1_TXID=${SENDERTXID[0]}
    UTXO1_VOUT=${SENDERVOUT[0]}
    CHANGE_ADDR=$($BITCOINCLI $DATADIR -rpcwallet=$1 getrawchangeaddress)
#    OP_RETURN_DATA="4920676f74206d792073616c6172792c204920616d20726963682e"
    OP_RETURN_DATA=$(echo $2 | xxd -p)
    DATA=$(echo "$OP_RETURN_DATA" | xxd -r -p)
    echo "Writing OP_RETURN: $DATA ..."

    HEX=$($BITCOINCLI $DATADIR -rpcwallet=$1 -named createrawtransaction inputs='''[{"txid": "'$UTXO1_TXID'", "vout": '$UTXO1_VOUT' }]''' outputs='''{ "data": "'$OP_RETURN_DATA'", "'$CHANGE_ADDR'": 39.9998 }''')   
}

cleanup(){
    $BITCOINCLI $DATADIR stop
    sleep 2
    rm -rf /home/$USER/.bitcoin/tmp
}

#SETUP
setup
install_jq
start_bitcoind

#PART I
#1. CREATE 3 WALLETS
create_wallet Miner false false
create_wallet Employer false false
create_wallet Employee false false

#2. Fund wallets by mining blocks and sending coins to Employer
mine_new_blocks Miner 102
EMPLOYER1=$(create_address Employer)
TXID1=$(send_coins Miner $EMPLOYER1 50)
mine_new_blocks Miner 1

#3 - 4. Create a salary transaction of 40BTC, where the Employer pays the Employee
create_transaction Employer Employee
sign_transaction Employer "$HEX"

#5. Report in a comment what happens when you try to broadcast this transaction.
<<comment 
Sending transaction with locktime 500 when blockheight is only 103 results in error message

error code -26
error message:
non-final

getmempoolentry returns transaction not in mempool
This is because most Bitcoin mempools will not allow you to place a timelocked transaction in their mempool until the timelock has expired.
comment

#6. Mine up to the 500th block and broadcast transaction.
mine_new_blocks Miner 397
send_transaction Employer
mine_new_blocks Miner 1

#7. Print final balances of Employee and Employer
echo "Employee balance: $(get_balance Employee) BTC"
echo "Employer balance: $(get_balance Employer) BTC"

#PART II
#1. Create a spending transaction where the Employee spends the funds to a new Employee address
#2. Add an OP_RETURN output in the spending transaction with the string data "I got my salary, I am rich"
create_opreturn Employee "I got my salary, I am rich"

#3. Extract and broadcast the fully signed transaction
sign_transaction Employee "$HEX"
send_transaction Employee
mine_new_blocks Miner 1

#4. Print the final balances of the Employee and Employer
echo "Employee balance: $(get_balance Employee) BTC"
echo "Employer balance: $(get_balance Employer) BTC"

#CLEANUP
cleanup


