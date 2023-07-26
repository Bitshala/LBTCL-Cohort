#!/bin/bash


# starting bitcoin core
bitcoind -daemon

# creating a wallet named Miner
bitcoin-cli createwallet “Miner”

# creating a wallet named Trader
bitcoin-cli createwallet “Trader”

# loading ‘Miner’ wallet 
bitcoin-cli loadwallet “Miner”

# generating an address for 'Miner' Wallet 
miner_address=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward”)

# loading ‘Trader’ wallet 
bitcoin-cli loadwallet “Trader”

# generating an address for ‘Trader’ Wallet 
trader_address=$(bitcoin-cli -rpcwallet=Trader getnewaddress “Received”)

# funding ‘Miner’ with 3 block rewards
bitcoin-cli generatetoaddress 3 $miner_address

# mining 100 blocks to  confirm the three coinbase transactions
bitcoin-cli -rpcwallet=Miner -generate 100

# checking the unspent transactions associated with wallet ‘Miner’
bitcoin-cli -rpcwallet=Miner listunspent

# selecting two UTXOs worth 50 BTC each 

$txid1=$(bitcoin-cli listunspent | jq -r ‘.[0] | .txid')
$vout1=$(bitcoin-cli listunspent | jq -r ‘.[0] | .vout’)
$txid2=$(bitcoin-cli listunspent | jq -r ‘.[1] | .txid')
$vout2=$(bitcoin-cli listunspent | jq -r ‘.[2] | .vout’)

# crafting a transaction from Miner to Trader and signalling RBF
parent=$(bitcoin-cli  -rpcwallet=Miner createrawtransaction '[
    {
        "txid": $txid1,
        "vout": $vout1,
        "sequence": 1
    },
    {
        "txid": $txid2,
        "vout": $vout2,
        "sequence": 1
    }
]' '{
    $trader_address: 70.0,
    $miner_address: 29.999
}' )

# signing the transaction
signed_parent=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $parent | jq -r '.hex' )

# broadcasting the transaction 
parent_tx_id=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_parent)


# making queries to the node’s mempool to get the ‘Parent’ transaction details   
parent_tx_details=$(bitcoin-cli  getrawmempool $parent_tx_id)

# extracting details to print 

trader_txid=$(echo $parent_tx_details | jq -r '.ancestors[0].txid')
trader_vout=$(echo $parent_tx_details  | jq -r '.ancestors[0].vout')
miner_txid=$(echo $parent_tx_details  | jq -r '.ancestors[1].txid')
miner_vout=$(echo $parent_tx_details | jq -r '.ancestors[1].vout')
miner_scriptpubkey=$(echo "$parent_tx_details”  | jq -r '.ancestors[1].scriptPubKey.hex')
miner_amount=$(echo $parent_tx_details  | jq -r '.ancestors[1].value')
trader_scriptpubkey=$(echo $parent_tx_details | jq -r '.vout[0].scriptPubKey.hex')
trader_amount=$(echo $parent_tx_details  | jq -r '.ancestors[0].value')
fees=$(echo $parent_tx_details  | jq -r '.modifiedfee')
weight=$(echo $parent_tx_details  | jq -r '.weight')


# crafting JSON


JSON='{
    "input": [
      {
        "txid": $trader_txid,
        "vout": $trader_vout
      },
      {
        "txid": $miner_txid,
        "vout": $miner_vout
      }
    ],
    "output": [
      {
        "script_pubkey": $miner_scriptpubkey,
        "amount": $miner_amount
      },
      {
        "script_pubkey": $trader_scriptpubkey,
        "amount": $trader_amount
      }
    ],
    "Fees": $fees,
    "Weight": $weight
}’


# printing JSON
echo $JSON


# creating a new transaction that spends from the above transaction and calling it Child

child=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '[
    {"txid": $parent_tx_id, "vout": $miner_vout}
]' '{
    "'$miner_new_address'": 29.900
}')


# signing the child transaction 

signed_child=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $child | jq -r '.hex')

# broadcasting the child transaction

child_tx_id=$(bitcoin-cli -rpcwallet=Miner sendrawtransaction $signed_child)

# making a getmempool entry query for the child transaction

child_tx_details1=$(bitcoin-cli  getmempoolentry $child_tx_id)

# printing the output 

echo $child_tx_details

# bumping the fee of the transaction 

bumped_parent_tx=(bitcoin-cli -rpcwallet=Miner bumpfee $parent_tx_id)

# signing the RBF transaction

signed_bumped_tx=(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $bumped_parent_tx | jq -r ‘.hex’)

# broadcasting the RBF transaction
bumped_parent_tx_id=(bitcoin-cli -rpcwallet=Miner sendrawtransaction $bumped_parent_tx_id)

# making a getmempool entry query for the child transaction

child_tx_details2=$(bitcoin-cli  getmempoolentry $child_tx_id)

# printing the output 

echo $child_tx_details


# explanation

: '
When we create a raw transaction, sign and broadcast it, but don't mine it, it will be in the mempool,
waiting to be included in a block by a miner. We call this transaction "Parent."

Then, when we create another raw transaction using the output of the "Parent" transaction as an input, sign and broadcast it, but don't mine it, it will also be in the mempool, waiting to be included in a block.
We call this transaction "Child."

Now, if we bump the fee of the "Parent" transaction and sign and broadcast it again, it will create a new version of the "Parent" transaction with a higher fee. This new version will replace the old version in the mempool, but the "Child" transaction will still reference the old version as its input.

When we make the first getmempoolentry query for the "Child" transaction, it will show details of the transaction with the old version of the "Parent" transaction as its input. However, after we bump the fee and sign and broadcast the new version of the "Parent" transaction, and then make the second getmempoolentry query for the "Child" transaction,we will notice that the details have changed.

The second getmempoolentry query will show that the "Child" transaction now references the new version of the "Parent" transaction with the higher fee as its input. This is because the "Child" transaction depends on the specific transaction output (UTXO) from the "Parent" transaction, and when the "Parent" transaction is replaced by a new version with a higher fee,
the "Child" transaction automatically references the new version.

In summary, the first getmempoolentry query for the "Child" transaction will show details of the "Child" transaction with
the old version of the "Parent" transaction as its input. The second getmempoolentry query for the "Child" transaction will
show details of the "Child" transaction with the new version of the "Parent" transaction (bumped with a higher fee) as its input.

Also, the base and modified fee fields will reflect the fee amount after the fee bump.
'



















