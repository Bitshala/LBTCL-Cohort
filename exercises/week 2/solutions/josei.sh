#!/bin/bash
# Week #2

echo "Create two wallets named Miner and Trader."
bitcoin-cli -named createwallet wallet_name="Trader" descriptors=false >/dev/null
bitcoin-cli -named createwallet wallet_name="Miner" descriptors=false >/dev/null

echo "Generate one address from the Miner wallet"
minerAddress=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner address" legacy)

echo "Fund the Miner wallet with at least 3 block rewards worth of satoshis (Starting balance: 150 BTC)."
bitcoin-cli generatetoaddress 103 $minerAddress > /dev/null

echo "Craft a transaction from Miner to Trader with the following structure (let's call it the Parent transaction):"
#
#       Input[0]: 50 BTC block reward.
input0=$(bitcoin-cli -rpcwallet=Miner listunspent|jq -r '.[0] |.txid')
vout0=$(bitcoin-cli -rpcwallet=Miner listunspent|jq -r '.[0] |.vout')

#       Input[1]: 50 BTC block reward.
input1=$(bitcoin-cli -rpcwallet=Miner listunspent|jq -r '.[1] |.txid')
vout1=$(bitcoin-cli -rpcwallet=Miner listunspent|jq -r '.[1] |.vout')

#       Output[0]: 70 BTC to Trader.
traderAddress=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Receive" legacy)

#       Output[1]: 29.99999 BTC change-back to Miner.
changeAddress=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Change" legacy)

#       Signal for RBF (Enable RBF for the transaction).
parentTX=$(bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[ { "txid": "'$input0'", "vout": '$vout0', "sequence": 1 }, { "txid": "'$input1'", "vout": '$vout1' } ]''' outputs='''{ "'$traderAddress'": 70, "'$changeAddress'": 29.99999}''')

echo "Sign and broadcast the Parent transaction but do not mine it yet." 
signedTX=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$parentTX | jq -r '.hex')
transactionID=$(bitcoin-cli -rpcwallet=Miner -named sendrawtransaction hexstring=$signedTX)

#Create JSON
input0TXID=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vin|.[0]|.txid')
input0VOUT=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vin|.[0]|.vout')
input1TXID=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vin|.[1]|.txid')
input1VOUT=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vin|.[1]|.vout')
output0Script=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vout|.[0]|.scriptPubKey')
output0Amount=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vout|.[0]|.value')
output1Script=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vout|.[1]|.scriptPubKey')
output1Amount=$(bitcoin-cli -rpcwallet=Miner decoderawtransaction $parentTX|jq -r '.vout|.[1]|.value')
totalInput=$(bitcoin-cli decoderawtransaction $parentTX |jq -r '.vout  [] | .value' | awk '{s+=$1} END {print s}')
fees=$(echo $totalInput - $output0Amount - $output1Amount| bc )
weight=$(bitcoin-cli decoderawtransaction $parentTX|jq -r '.vsize')


json=$( jq -n \
            --arg txid0 "'$input0TXID'" \
            --arg txid1 "'$input1TXID'" \
            --arg vout0 "'$input0VOUT'" \
            --arg vout1 "'$input1VOUT'" \
            --arg script0 "'$output0Script'" \
            --arg script1 "'$output1Script'" \
            --arg amount0 "'$output0Amount'" \
            --arg amount1 "'$output1Amount'" \
            --arg fees "'$fees'" \
            --arg weight "$weight" \
            '{input: [{ txid: $txid0, vout: $vout0 }, { txid: $txid1, vout: $vout1 } ], output: [{ script_pubkey: $script0, amount: $amount0 }, { script_pubkey: $script1, amount: $amount1 } ], Fees: $fees, Weight: $weight }'
)

echo $json|jq

echo "Create a broadcast new transaction that spends from the above transaction (the Parent). Let's call it the Child transaction" 
echo "Generate new address from the Miner wallet"
newMinerAddress=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Miner new address" legacy)
childTX=$(bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[ { "txid": "'$transactionID'", "vout": 1}]''' outputs='''{ "'$newMinerAddress'": 29.99998}''')

echo "Sign and broadcast the Child transaction" 
signedChildTX=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$childTX | jq -r '.hex')
childTransactionID=$(bitcoin-cli -rpcwallet=Miner -named sendrawtransaction hexstring=$signedChildTX)

echo "Make a getmempoolentry query for the Child transaction and print the output."
bitcoin-cli -rpcwallet=Miner getmempoolentry $childTransactionID 

echo "Generate new address from the Trader wallet for conflicting transaction"
newTraderAddress=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Trader new address" legacy)
conflictingTX=$(bitcoin-cli -rpcwallet=Miner -named createrawtransaction inputs='''[ { "txid": "'$input0'", "vout": '$vout0', "sequence": 1 }, { "txid": "'$input1'", "vout": '$vout1' } ]''' outputs='''{ "'$newTraderAddress'": 50, "'$changeAddress'": 49.99989}''')

echo "Sign and broadcast the Conflicting transaction" 
signedConflictingTX=$(bitcoin-cli -rpcwallet=Miner -named signrawtransactionwithwallet hexstring=$conflictingTX | jq -r '.hex')
conflictingTXID=$(bitcoin-cli -rpcwallet=Miner -named sendrawtransaction hexstring=$signedConflictingTX)

echo "Make another getmempoolentry query for the Child transaction and print the result."
bitcoin-cli -rpcwallet=Miner getmempoolentry $childTransactionID

echo "===============The child transaction has been removed from the mempool, as it has been replaced by the Conflicting Transaction==============="
