#!/bin/bash
# Week #3

# Restart node script I was using in a separate file
:'
bitcoin-cli stop
sleep 1
rm -rf /home/jose/.bitcoin/regtest/*
bitcoind -daemon
sleep 5
'

# End of node "restarting"


echo "Create three wallets: Miner, Alice, and Bob."
bitcoin-cli -named createwallet wallet_name="Miner" descriptors=false >/dev/null
bitcoin-cli -named createwallet wallet_name="Alice" descriptors=false >/dev/null
bitcoin-cli -named createwallet wallet_name="Bob" descriptors=false >/dev/null
echo "--------------------------------------------------"

echo "Fund the wallets by generating some blocks for Miner and sending some coins to Alice and Bob."
minerAddress=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner address" )
aliceAddress=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Alice address" )
bobAddress=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Bob address" )
bitcoin-cli generatetoaddress 101 $minerAddress > /dev/null
TXIDAlice=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $aliceAddress 20)
TXIDBob=$(bitcoin-cli -rpcwallet=Miner sendtoaddress $bobAddress 20)
bitcoin-cli generatetoaddress 1 $minerAddress > /dev/null
voutAlice=$(bitcoin-cli -rpcwallet=Alice listunspent |jq -r '.[0]|.vout')
voutBob=$(bitcoin-cli -rpcwallet=Bob listunspent |jq -r '.[0]|.vout')
echo "Alice's balance: " 
bitcoin-cli -rpcwallet=Alice getbalance
#bitcoin-cli -rpcwallet=Alice listunspent
echo "Bob's balance: " 
bitcoin-cli -rpcwallet=Bob getbalance
#bitcoin-cli -rpcwallet=Bob listunspent
echo "--------------------------------------------------"


echo "Create a 2-of-2 Multisig address by combining public keys from Alice and Bob."
aliceMultiAddress=$(bitcoin-cli -rpcwallet=Alice getnewaddress )
aliceMultiPubKey=$(bitcoin-cli -rpcwallet=Alice -named getaddressinfo address=$aliceMultiAddress | jq -r '.pubkey')
bobMultiAddress=$(bitcoin-cli -rpcwallet=Bob getnewaddress )
bobMultiPubKey=$(bitcoin-cli -rpcwallet=Bob -named getaddressinfo address=$bobMultiAddress | jq -r '.pubkey')

#echo "Alice Address and Bob PubKey"
#echo $aliceMultiAddress
#echo $bobMultiPubKey
multisigAddress=$(bitcoin-cli -rpcwallet=Alice -named addmultisigaddress label="Multisig Address" nrequired=2 keys='''["'$aliceMultiAddress'","'$bobMultiPubKey'"]''' |jq -r '.address')
echo "Multisig Address: "
echo $multisigAddress
#multisigAddress2=$(bitcoin-cli -rpcwallet=Bob -named addmultisigaddress nrequired=2 keys='''["'$aliceMultiPubKey'","'$bobMultiAddress'"]''')
#echo $multisigAddress2
echo "--------------------------------------------------"

echo "Create a Partially Signed Bitcoin Transaction (PSBT) to fund the multisig address with 20 BTC, taking 10 BTC each from Alice and Bob, and providing correct change back to each of them."
aliceChangeAddress=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Alice change address" )
bobChangeAddress=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Bob change address" )
psbt=$(bitcoin-cli -rpcwallet=Alice -named createpsbt inputs='''[ { "txid": "'$TXIDAlice'", "vout": '$voutAlice' }, { "txid": "'$TXIDBob'", "vout": '$voutBob' } ]''' outputs='''{ "'$multisigAddress'": 20,"'$aliceChangeAddress'": 9.999998,"'$bobChangeAddress'": 9.999998 }''')
echo "TXID for funding Multi Signature address: "
echo $psbt

echo "--------------------------------------------------"
#echo "Decode not signed psbt: "
#bitcoin-cli -rpcwallet=Alice decodepsbt $psbt
echo "--------------------------------------------------"


psbtAlice=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $psbt | jq -r '.psbt')
psbtBob=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $psbt | jq -r '.psbt')
combinedpsbt=$(bitcoin-cli -rpcwallet=Alice combinepsbt '''["'$psbtAlice'", "'$psbtBob'"]''' )

#echo "Analyze signed psbt: "
#bitcoin-cli -rpcwallet=Alice analyzepsbt $combinedpsbt
finalizedpsbthex=$(bitcoin-cli -rpcwallet=Alice finalizepsbt $combinedpsbt | jq -r '.hex')

echo "Sending raw TX"
bitcoin-cli -rpcwallet=Alice -named sendrawtransaction hexstring=$finalizedpsbthex
echo "--------------------------------------------------"

echo "Confirm the balance by mining a few more blocks."
bitcoin-cli generatetoaddress 1 $(bitcoin-cli -rpcwallet=Miner getnewaddress) > /dev/null
echo "--------------------------------------------------"

echo "Print the final balances of Alice and Bob."
echo "Alice's balance: " 
bitcoin-cli -rpcwallet=Alice getbalance
echo "Bob's balance: " 
bitcoin-cli -rpcwallet=Bob getbalance
echo "--------------------------------------------------"

echo " "

echo "--------------------------------------------------Settle Multisig--------------------------------------------------"
echo "Create a PSBT to spend funds from the multisig, ensuring 10 BTC is equally distributed back between Alice and Bob after accounting for fees."
bitcoin-cli -rpcwallet=Alice importaddress $multisigAddress
bitcoin-cli -rpcwallet=Bob importaddress $multisigAddress

#Get Multisig Address TXID and Vout to use as input in PSBT
multisigTXID=$(bitcoin-cli -rpcwallet=Alice listunspent|jq -r '.[0]|.txid')
multisigVout=$(bitcoin-cli -rpcwallet=Alice listunspent|jq -r '.[0]|.vout')
#echo "New Multisig TXID and Vout: "
#echo $multisigTXID
#echo $multisigVout

#Get addresses for Alice and Bob to receive PSBT
aliceReturnAddress=$(bitcoin-cli -rpcwallet=Alice getnewaddress "Alice return address" )
bobReturnAddress=$(bitcoin-cli -rpcwallet=Bob getnewaddress "Bob return address" )
#echo "New addresses for Alice and Bob"
#echo $aliceReturnAddress
#echo $bobReturnAddress

#Create new PSBT TX
newpsbt=$(bitcoin-cli -named createpsbt inputs='''[ { "txid": "'$multisigTXID'", "vout": '$multisigVout' } ]''' outputs='''{ "'$aliceReturnAddress'": 9.999998, "'$bobReturnAddress'": 9.999998 }''')


#Instead of individually signing the psbt, chain the signing process.
#
#    Sign by Alice first. Get the signed .psbt.
#    Use the same psbt and sign it by BOB.

echo "#Get Alice to sign"
aliceNewPSBT=$(bitcoin-cli -rpcwallet=Alice walletprocesspsbt $newpsbt | jq -r '.psbt')
bitcoin-cli analyzepsbt $aliceNewPSBT
echo "#Get Bob to sign"
bothNewPSBT=$(bitcoin-cli -rpcwallet=Bob walletprocesspsbt $aliceNewPSBT | jq -r '.psbt')


#
#In the above process no need to join the two psbts again. Bob's signed psbt output will be the final psbt.
#

#echo "#Join signatures"
#newSignedPSBT=$(bitcoin-cli combinepsbt '''["'$aliceNewPSBT'", "'$bobNewPSBT'"]''')
#bitcoin-cli decodepsbt $newSignedPSBT
#bitcoin-cli analyzepsbt $newSignedPSBT
bitcoin-cli analyzepsbt $bothNewPSBT
echo "--------------------------------------------------"
echo "#Finalize and Send New Signed PSBT" 
echo "--------------------------------------------------"
newSignedPSBTHex=$(bitcoin-cli finalizepsbt $bothNewPSBT | jq -r '.hex')


#
#do not use the wallet here. Just bitcoin-cli sendrawtransaction. For some reason using wallet will fail to broadcast.
#
#bitcoin-cli -rpcwallet=Alice sendrawtransaction hexstring=$newSignedPSBTHex
bitcoin-cli sendrawtransaction $newSignedPSBTHex > /dev/null


#mining one more block in order to see the transaction reflected in Alice's and Bob's wallet
minerAddress=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner address" )
bitcoin-cli generatetoaddress 1 $minerAddress > /dev/null


echo "Alice's balance: " 
bitcoin-cli -rpcwallet=Alice getbalance
#bitcoin-cli -rpcwallet=Alice listunspent
echo "Bob's balance: " 
bitcoin-cli -rpcwallet=Bob getbalance
#bitcoin-cli -rpcwallet=Bob listunspent
echo "--------------------------------------------------"
