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
    ADDR=$($BITCOINCLI $DATADIR -rpcwallet=$2 getnewaddress)
    $BITCOINCLI $DATADIR -rpcwallet=$1 -named sendtoaddress address="$ADDR" amount="$3" fee_rate=25 > /dev/null
}

get_balance(){
    BALANCE=$($BITCOINCLI $DATADIR -named -rpcwallet=$1 getbalance)
    echo "$1 has a blance of $BALANCE BTC"
}

create_transaction(){
    SENDERTXID=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .txid'))
    SENDERVOUT=($($BITCOINCLI $DATADIR -rpcwallet=$1 listunspent | jq -r '.[] | .vout'))
    
    UTXO1_TXID=${SENDERTXID[0]}
    UTXO1_VOUT=${SENDERVOUT[0]}
    RECEIVER_ADDR=$(create_address $2)
    CHANGE_ADDR=$($BITCOINCLI $DATADIR -rpcwallet=$1 getrawchangeaddress)

    HEX=$($BITCOINCLI $DATADIR -rpcwallet=$1 -named createrawtransaction inputs='''[{"txid": "'$UTXO1_TXID'", "vout": '$UTXO1_VOUT', "sequence": '10' }]''' outputs='''{"'$RECEIVER_ADDR'": 10.0, "'$CHANGE_ADDR'": 9.9998 }''')   
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

decode_transaction(){
    $BITCOINCLI $DATADIR -rpcwallet=$1 decoderawtransaction $HEX
}

#decode_script(){
#    SCRIPTHEX=$($BITCOINCLI $DATADIR -rpcwallet=$1 decoderawtransaction $HEX | jq -r '.vout')
#    $BITCOINCLI $DATADIR decodescript 
#}

cleanup(){
    $BITCOINCLI $DATADIR stop
    sleep 2
    rm -rf /home/$USER/.bitcoin/tmp
}


#SETUP
setup
install_jq
start_bitcoind

#SETUP A RELATIVE TIMELOCK
#1 Create two wallets: Miner and Alice.
create_wallet Miner false false
create_wallet Alice false false

#2. Fund the wallets by generating some blocks for Miner and sending some coins to Alice.
mine_new_blocks Miner 101
send_coins Miner Alice 20

#3. Confirm the transaction and assert that Alice has a positive balance.
mine_new_blocks Miner 1
get_balance Alice

#4. Create a transaction where Alice pays 10 BTC back to Miner, but with a relative timelock of 10 blocks.
create_transaction Alice Miner

#5. Report in the terminal output what happens when you try to broadcast the 2nd transaction.
sign_transaction Alice "$HEX"
echo "When you try to broadcast this timelocked transaction, Bitcoin Core produces an error message with error code: -26 and the message 'non-BIP68-final' because the transaction will not be relayed by nodes until the relative timelock has expired." 
decode_transaction

#SPEND FROM RELATIVE TIMELOCK 
#1. Generate 10 more blocks.
mine_new_blocks Miner 10

#2. Broadcast the 2nd transaction. Confirm it by generating one more block.
send_transaction Alice
mine_new_blocks Miner 1

#3. Report balance of Alice.
get_balance Alice

#CLEANUP
#cleanup
