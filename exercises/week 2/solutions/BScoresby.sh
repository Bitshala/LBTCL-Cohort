#!/bin/bash

setup(){
    mkdir -p /home/$USER/.bitcoin/tmp;
    touch /home/$USER/.bitcoin/tmp/bitcoin.conf
    echo "regtest=1  
	fallbackfee=0.0001
        server=1
        txindex=1
        daemon=1" >> /home/$USER/.bitcoin/tmp/bitcoin.conf
}

install_jq(){
    if ! command -v jq &> /dev/null
    then
        sudo apt-get install jq
    fi
}

start_bitcoind(){
    /usr/local/bin/bitcoin/bin/bitcoind -datadir=/home/$USER/.bitcoin/tmp -daemon
    sleep 5
}

create_wallet(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named createwallet wallet_name="$1"
}

create_address(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 getnewaddress
}

mine_new_blocks(){
    MINER1=`create_address $1`
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp generatetoaddress $2 "$MINER1" > /dev/null
}


create_parent_transaction(){
    MINERTXID=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner listunspent | jq -r '.[] | .txid'))
    MINERVOUT=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner listunspent | jq -r '.[] | .vout'))
    
    UTXO1_TXID=${MINERTXID[0]}
    UTXO1_VOUT=${MINERVOUT[0]}
    UTXO2_TXID=${MINERTXID[1]}
    UTXO2_VOUT=${MINERVOUT[0]}
    TRADER_ADDR=`create_address Trader`
    CHANGE_ADDR=`/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner getrawchangeaddress`

    PARENT=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'$UTXO1_TXID'", "vout": '$UTXO1_VOUT' }, {"txid": "'$UTXO2_TXID'", "vout": '$UTXO2_VOUT' }]''' outputs='''{"'$TRADER_ADDR'": 70.0, "'$CHANGE_ADDR'": 29.999 }''' replaceable=true)   
}

sign_transaction(){
    unset signedtx
    signedtx=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 -named signrawtransactionwithwallet hexstring=$2 | jq -r '.hex')
    echo "transaction signed"
}

send_transaction(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 -named sendrawtransaction hexstring=$signedtx
    echo "transaction sent"
}

get_mempool_info(){

    PARENT_TXID=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Trader listtransactions | jq -r '.[0] | .txid')
    FEES=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Trader getmempoolentry $PARENT_TXID | jq -r '.fees.base')
    WEIGHT=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Trader getmempoolentry $PARENT_TXID | jq -r '.weight')
    HEX=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Trader gettransaction $PARENT_TXID | jq -r '.hex')
    PARENT_INPUT_TXID=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $HEX | jq -r '.vin | .[] | .txid'))
    PARENT_INPUT_VOUT=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $HEX | jq -r '.vin | .[] | .vout'))
    PARENT_OUTPUT_AMOUNT=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $HEX | jq -r '.vout | .[] | .value'))
    PARENT_OUTPUT_SPUBKEY=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $HEX | jq -r '.vout | .[] | .scriptPubKey.hex'))
}

pretty_print(){
    VBYTES=$((WEIGHT/4))
    JSON=$(jq --null-input --arg fees "$FEES" --arg txid1 "${PARENT_INPUT_TXID[0]}" --arg txid2 "${PARENT_INPUT_TXID[1]}" --arg vout1 "${PARENT_INPUT_VOUT[0]}" --arg vout2 "${PARENT_INPUT_VOUT[1]}" --arg pubkey1 "${PARENT_OUTPUT_SPUBKEY[1]}" --arg pubkey2 "${PARENT_OUTPUT_SPUBKEY[0]}" --arg amount1 "${PARENT_OUTPUT_AMOUNT[1]}" --arg amount2 "${PARENT_OUTPUT_AMOUNT[0]}" --arg weight "$VBYTES" '{"input": [{"txid": $txid1, "vout": $vout1}, {"txid": $txid2, "vout": $vout2}], "outputs": [{"script_pubkey": $pubkey1, "amount": $amount1}, {"script_pubkey": $pubkey2, "amount": $amount2}], "Fees": $fees, "Weight": $weight }' )

    echo "${JSON}"
}

create_child_transaction(){
    PARENT_OUTPUT_VOUT=($(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $HEX | jq -r '.vout | .[] | .n'))
    MINER_ADDR_2=`create_address Miner`
    CHILD=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'$PARENT_TXID'", "vout": '${PARENT_OUTPUT_VOUT[1]}'}]''' outputs='''{"'$MINER_ADDR_2'": 29.99898 }''' replaceable=true)   
}

get_mempool_entry(){
    unset TXID
    TXID=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp decoderawtransaction $1 | jq -r '.txid')
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner getmempoolentry $TXID
}


bump_fee(){
    TRADER_ADDR=`create_address Trader`
    CHANGE_ADDR=`/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner getrawchangeaddress`
    PARENT_BUMP=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Miner -named createrawtransaction inputs='''[{"txid": "'$UTXO1_TXID'", "vout": '$UTXO1_VOUT' }, {"txid": "'$UTXO2_TXID'", "vout": '$UTXO2_VOUT' }]''' outputs='''{"'$TRADER_ADDR'": 70.0, "'$CHANGE_ADDR'": 29.9989 }''' replaceable=true)       
}

cleanup(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp stop
    sleep 2
    rm -rf /home/$USER/.bitcoin/tmp
}


#Setup
setup
sleep 1
start_bitcoind
install_jq

#1. Create two wallets named Miner and Trader
create_wallet Miner
create_wallet Trader

#2. Fund the Miner wallet with at least 3 block rewards worth of sats
mine_new_blocks Miner 103

#3. Craft a transaction from Miner to Trader called Parent transaction
create_parent_transaction

#4. Sign and broadcast the transaction
sign_transaction Miner "$PARENT"
send_transaction

#5. Make queries to the node's mempool to get Parent transaction details
get_mempool_info

#6 Print them as JSON in the terminal
pretty_print

#7 Create new transaction spending Miner's output
create_child_transaction
sign_transaction Miner "$CHILD"
send_transaction
sleep 1

#8 Make a new mempool query for the child transaction
get_mempool_entry "$CHILD"

#9 Fee bump Parent transaction by 10k sats
bump_fee

#10 Sign and broadcast RBF transaction
sign_transaction Miner "$PARENT_BUMP"
send_transaction

#11 Make another getmempool entry query for child
get_mempool_entry "$CHILD"

#12 explanation in the terminal of what changed and why
echo "The child transaction is no longer in this nodes mempool, because as far as this node is concerned the parent transaction has been replaced. Now, I'd be curious to have a look at a testnet or signet or mainnet version of this, because while this node may refuse to acknowledge the conflicting transactions, I wonder if all other nodes would acknowledge the RBF'd parent as the only legitimate transaction, or whether maybe older nodes would know how to deal with it. I guess it is standard mempool policy that the rbf'd transaction is always the legitimate one, but I still wonder about this a bit."

#Cleanup
cleanup

