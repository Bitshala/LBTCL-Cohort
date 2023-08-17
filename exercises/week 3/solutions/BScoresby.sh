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
    sleep 3
}

create_wallet(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named createwallet wallet_name="$1" disable_private_keys="$2" blank="$3" 1> /dev/null
}

create_address(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 getnewaddress
}

mine_new_blocks(){
    MINER1=`create_address $1`
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp generatetoaddress $2 "$MINER1" > /dev/null
}

send_coins(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 -named sendtoaddress address="$2" amount="$3" fee_rate=25 
}

get_address_pubkey(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$1 getaddressinfo address=$2 | jq -r '.pubkey'
}

get_balance(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$1 getbalance
}

list_unspent(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$1 listunspent
}

create_multi(){
    ALICE_INTERNAL_PUBKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
    ALICE_EXTERNAL_PUBKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
    BOB_INTERNAL_PUBKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$2 listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
    BOB_EXTERNAL_PUBKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$2 listdescriptors | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')

    EXTERNAL_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_EXTERNAL_PUBKEY","$BOB_EXTERNAL_PUBKEY"))"
    INTERNAL_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_INTERNAL_PUBKEY","$BOB_INTERNAL_PUBKEY"))"         
 
    EXTERNAL_DESC_SUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo $EXTERNAL_DESCRIPTOR | jq -r '.descriptor')
    INTERNAL_DESC_SUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo "$INTERNAL_DESCRIPTOR" | jq -r '.descriptor')

    MULTI_EXT_DESC="{\"desc\": \"$EXTERNAL_DESC_SUM\", \"active\": true, \"interal\": false, \"timestamp\": \"now\"}"
    MULTI_INT_DESC="{\"desc\": \"$INTERNAL_DESC_SUM\", \"active\": true, \"interal\": true, \"timestamp\": \"now\"}"

    MULTI_DESC="[$MULTI_EXT_DESC, $MULTI_INT_DESC]"
}

create_alice_signing_descriptor(){
    ALICE_INTERNAL_PRIVKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
    ALICE_EXTERNAL_PRIVKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
 
    EXTERNAL_PRIVKEY_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_EXTERNAL_PRIVKEY","$BOB_EXTERNAL_PUBKEY"))"
    INTERNAL_PRIVKEY_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_INTERNAL_PRIVKEY","$BOB_INTERNAL_PUBKEY"))"         

    EXTERNAL_PRIVKEY_CHECKSUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo $EXTERNAL_PRIVKEY_DESCRIPTOR | jq -r '.checksum')
    INTERNAL_PRIVKEY_CHECKSUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo "$INTERNAL_PRIVKEY_DESCRIPTOR" | jq -r '.checksum')
    
    EXTERNAL_PRIVKEY_DESC_SUM=${EXTERNAL_PRIVKEY_DESCRIPTOR}#${EXTERNAL_PRIVKEY_CHECKSUM}
    INTERNAL_PRIVKEY_DESC_SUM=${INTERNAL_PRIVKEY_DESCRIPTOR}#${INTERNAL_PRIVKEY_CHECKSUM}

    ALICE_EXT_DESC="{\"desc\": \"$EXTERNAL_PRIVKEY_DESC_SUM\", \"active\": true, \"interal\": false, \"timestamp\": \"now\"}"
    ALICE_INT_DESC="{\"desc\": \"$INTERNAL_PRIVKEY_DESC_SUM\", \"active\": true, \"interal\": true, \"timestamp\": \"now\"}"

    ALICE_DESC="[$ALICE_EXT_DESC, $ALICE_INT_DESC]"
}

create_bob_signing_descriptor(){
    BOB_INTERNAL_PRIVKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/1/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
    BOB_EXTERNAL_PRIVKEY=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob listdescriptors true | jq -r '.descriptors | [.[] | select(.desc | startswith("wpkh") and contains("/0/*"))][0] | .desc' | grep -Po '(?<=\().*(?=\))')
 
    EXTERNAL_PRIVKEY_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_EXTERNAL_PUBKEY","$BOB_EXTERNAL_PRIVKEY"))"
    INTERNAL_PRIVKEY_DESCRIPTOR="wsh(sortedmulti(2,"$ALICE_INTERNAL_PUBKEY","$BOB_INTERNAL_PRIVKEY"))"         

    EXTERNAL_PRIVKEY_CHECKSUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo $EXTERNAL_PRIVKEY_DESCRIPTOR | jq -r '.checksum')
    INTERNAL_PRIVKEY_CHECKSUM=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp getdescriptorinfo "$INTERNAL_PRIVKEY_DESCRIPTOR" | jq -r '.checksum')
    
    EXTERNAL_PRIVKEY_DESC_SUM=${EXTERNAL_PRIVKEY_DESCRIPTOR}#${EXTERNAL_PRIVKEY_CHECKSUM}
    INTERNAL_PRIVKEY_DESC_SUM=${INTERNAL_PRIVKEY_DESCRIPTOR}#${INTERNAL_PRIVKEY_CHECKSUM}

    BOB_EXT_DESC="{\"desc\": \"$EXTERNAL_PRIVKEY_DESC_SUM\", \"active\": true, \"interal\": false, \"timestamp\": \"now\"}"
    BOB_INT_DESC="{\"desc\": \"$INTERNAL_PRIVKEY_DESC_SUM\", \"active\": true, \"interal\": true, \"timestamp\": \"now\"}"

    BOB_DESC="[$ALICE_EXT_DESC, $ALICE_INT_DESC]"
}

import_descriptors(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 importdescriptors "$2"
}

funding_psbt(){
    TXID1=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$1 listunspent | jq -r '.[0] | .txid')
    VOUT1=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$1 listunspent | jq -r '.[0] | .vout')
    TXID2=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$2 listunspent | jq -r '.[0] | .txid')
    VOUT2=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named -rpcwallet=$2 listunspent | jq -r '.[0] | .vout')
    ALICE_CHANGE=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice getrawchangeaddress)
    BOB_CHANGE=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob getrawchangeaddress)
    MULTI_ADDR=$(create_address Multi)

    PSBT1=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named createpsbt inputs='''[ { "txid": "'$TXID1'", "vout": '$VOUT1' }, { "txid": "'$TXID2'", "vout": '$VOUT2' } ]''' outputs='''[ { "'$MULTI_ADDR'": 20 }, { "'$ALICE_CHANGE'": 19.9998 }, { "'$BOB_CHANGE'": 19.9998 } ]''' ) 

#updating psbt
    PSBT1A=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice walletprocesspsbt "$PSBT1" | jq -r '.psbt')

    PSBT1AB=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob walletprocesspsbt "$PSBT1A" | jq -r '.psbt')

#finalizing psbt    
    HEX=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob finalizepsbt "$PSBT1AB" | jq -r '.hex')

#broadcasting psbt
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob -named sendrawtransaction hexstring=$HEX
}

spending_psbt(){
    ALICE_ADDR2=$(create_address Alice)
    BOB_ADDR2=$(create_address Bob)
    MULTI_CHANGE_ADDR2=$(create_address Multi)
    MULTI_TXID_1=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 listunspent | jq -r '.[0] | .txid')
    MULTI_VOUT_1=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=$1 listunspent | jq '.[0] | .vout')

    PSBT2=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -named createpsbt inputs='''[ { "txid": "'$MULTI_TXID_1'", "vout": '$MULTI_VOUT_1' } ]''' outputs='''[ { "'$ALICE_ADDR2'": 5 }, { "'$BOB_ADDR2'": 5 }, { "'$MULTI_CHANGE_ADDR2'" : 9.998 } ]''' ) 
}

sign_spending_psbt(){
    PSBT2A=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice walletprocesspsbt "$PSBT2" | jq -r '.psbt')

    PSBT2AB=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob walletprocesspsbt "$PSBT2A" | jq -r '.psbt')

    HEX=$(/usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Alice finalizepsbt "$PSBT2AB" | jq -r '.hex')

#broadcasting psbt
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp -rpcwallet=Bob -named sendrawtransaction hexstring=$HEX
}

cleanup(){
    /usr/local/bin/bitcoin/bin/bitcoin-cli -datadir=/home/$USER/.bitcoin/tmp stop
    sleep 2
    rm -rf /home/$USER/.bitcoin/tmp
}


#Setup
setup
install_jq
start_bitcoind

#SETUP MULTISIG
#1. Create three wallets: Miner, Alice and Bob
create_wallet Miner false false
create_wallet Alice false false
create_wallet Bob false false

#2. Fund the wallets by generating some blocks and sending coins to Alice and Bob
mine_new_blocks Miner 103
ALICE1=$(create_address Alice)
BOB1=$(create_address Bob)
TXIDA=$(send_coins Miner $ALICE1 30)
TXIDB=$(send_coins Miner $BOB1 30)
mine_new_blocks Miner 1
get_balance Alice
get_balance Bob

#3. Create 2 of 2 Multisig for Alice and Bob
create_multi Alice Bob
create_wallet Multi true true
import_descriptors Multi "$MULTI_DESC"

#4. Create PSBT funding multisig with 20BTC
funding_psbt Alice Bob

#5. Confirm balance by mining a few more blocks
mine_new_blocks Miner 3

#6. Print final balances of Alice and Bob
echo "Alice balance: $(get_balance Alice)"
echo "Bob balance: $(get_balance Bob)"

#SETTLE MULTISIG
#1. Create PSBT to spend from multisig
spending_psbt Multi

#2. - 4. Sign the PSBT with Alice and Bob wallets, extract and broadcast transaction.
create_alice_signing_descriptor
import_descriptors Alice "$ALICE_DESC"
create_bob_signing_descriptor
import_descriptors Bob "$BOB_DESC"
sign_spending_psbt

#5. Mine new blocks to confirm transaction and print balances for Alice and Bob
mine_new_blocks Miner 1
echo "Alice balance: $(get_balance Alice)"
echo "Bob balance: $(get_balance Bob)"

#Cleanup
cleanup
