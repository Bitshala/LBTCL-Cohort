#!/bin/bash


clear
echo "LBTCL Cohort Week 2 Script"
read -n 1 -s -r -p "Press any key to continue"
clear
bitcoind -daemon
sleep 5
echo "Creating wallets .... "
bitcoin-cli createwallet "Miner"
bitcoin-cli createwallet "Trader"
bitcoin-cli loadwallet Miner > /dev/null
bitcoin-cli loadwallet Trader > /dev/null
mineraddr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "Mining Reward")
traderaddr=$(bitcoin-cli -rpcwallet=Trader getnewaddress "Trader")

echo "Generating some blocks .... "
bitcoin-cli generatetoaddress 103 $mineraddr > /dev/null

echo "Creating Parent Tx .... "
input_0=$(bitcoin-cli -rpcwallet=Miner listunspent | jq ".[0].txid")
input_1=$(bitcoin-cli -rpcwallet=Miner listunspent | jq ".[1].txid")
output_amount=70
change_amount=29.99999
parent_tx_hex=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '[{"txid":'$input_0',"vout":0},{"txid":'$input_1',"vout":0}]' '[{"'$traderaddr'":'$output_amount'},{"'$mineraddr'":'$change_amount'}]')
signed_parent_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $parent_tx_hex | jq ".hex" | tr -d '"')
parent_txid=$(bitcoin-cli sendrawtransaction $signed_parent_tx)
echo "Parent Tx broadcasted with txid: $parent_txid"
bitcoin-cli getmempoolentry $parent_txid 
read -n 1 -s -r -p "Press any key to continue"
clear
echo '{"input":[{"txid":"'$input_0'","vout":0},{"txid":"'$input_1'",vout:0}],"output":[{"script_pubkey":"'$mineraddr'","amount":'$output_amount'},{"script_pubkey":"'$traderaddr'","amount":"'$change_amount'"}],"fees":"'$(bitcoin-cli getmempoolentry $parent_txid | jq ".fees.base")'","Weight":"'$(bitcoin-cli getmempoolentry $parent_txid | jq ".weight")'"}' 
read -n 1 -s -r -p "Press any key to continue"
clear
echo "Creating child transaction .... "
new_mineraddr=$(bitcoin-cli -rpcwallet=Miner getnewaddress "New Miner")
child_tx_hex=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '[{"txid":"'$parent_txid'","vout":1}]' '[{"'$new_mineraddr'":29.99998}]')
signed_child_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $child_tx_hex | jq ".hex" | tr -d '"')
child_txid=$(bitcoin-cli sendrawtransaction $signed_child_tx)
echo "Child Tx broadcasted with txid: $child_txid"
bitcoin-cli getmempoolentry $parent_txid
bitcoin-cli getmempoolentry $child_txid  
read -n 1 -s -r -p "Press any key to continue"
clear
echo "Creating RBF of Parent Tx .... "
rbf_change_amount=29.99989
rbf_parent_tx_hex=$(bitcoin-cli -rpcwallet=Miner createrawtransaction '[{"txid":'$input_0',"vout":0},{"txid":'$input_1',"vout":0}]' '[{"'$traderaddr'":'$output_amount'},{"'$mineraddr'":'$rbf_change_amount'}]')
signed_rbf_parent_tx=$(bitcoin-cli -rpcwallet=Miner signrawtransactionwithwallet $rbf_parent_tx_hex | jq ".hex" | tr -d '"')
rbf_parent_txid=$(bitcoin-cli sendrawtransaction $signed_rbf_parent_tx)
echo "RBF Parent Tx broadcasted with txid: $rbf_parent_txid"
bitcoin-cli getmempoolentry $child_txid  
echo "The child tx is no more in the mempool since the new rbf replaces the old parent"
read -n 1 -s -r -p "This is the End.Press any key to continue"
clear
bitcoin-cli stop
exit