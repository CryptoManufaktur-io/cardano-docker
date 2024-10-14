#!/usr/bin/env bash
set -Eeuo pipefail
WORK_DIR=/runtime/keys
cd $WORK_DIR

Color_Off='\033[0m'       # Text Reset
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue

get_network(){
  if [[ "$NETWORK" == "preview" ]]; then
    command="--testnet-magic 2"
  elif [[ "$NETWORK" == "preprod" ]]; then
    command="--testnet-magic 1"
  else
    command="--mainnet"
  fi

  echo $command  
}

bash(){
    /bin/bash
}

gen-wallet() {
  if [ -e "payment.skey" ]; then
    echo "Wallet keys already generated. You can exec into container and check under '$WORK_DIR' folder"
    exit 0
  fi

  # Generating Payment Keys 
  cardano-cli $ERA address key-gen \
      --verification-key-file payment.vkey \
      --signing-key-file payment.skey

  # Generating Stake Keys
  cardano-cli $ERA stake-address key-gen \
      --verification-key-file stake.vkey \
      --signing-key-file stake.skey

  # Create your stake address from the stake address verification key
  cardano-cli $ERA stake-address build \
      --stake-verification-key-file stake.vkey \
      --out-file stake.addr \
      $(get_network)

  # Generating Wallet Keys
  cardano-cli $ERA address build \
      --payment-verification-key-file payment.vkey \
      --out-file payment.addr \
      $(get_network)
  
  echo "Wallet keys generated successfully, there are saved under '$WORK_DIR' inside container."
}

gen-block-producer() {
  if [ -e "cold.skey" ]; then
    echo "Block producer keys already generated. You can exec into container and check under '$WORK_DIR' folder"
    exit 0
  fi

  # Generating Cold Keys
  cardano-cli $ERA node key-gen \
      --cold-verification-key-file cold.vkey \
      --cold-signing-key-file cold.skey \
      --operational-certificate-issue-counter cold.counter

  # Generating KES Keys
  cardano-cli $ERA node key-gen-KES \
      --verification-key-file kes.vkey \
      --signing-key-file kes.skey

  # Generating VRF Keys
  cardano-cli $ERA node key-gen-VRF \
      --verification-key-file vrf.vkey \
      --signing-key-file vrf.skey
  chmod 400 vrf.skey
    
  echo "Block producer keys generated successfully, there are saved under '$WORK_DIR' inside container."
}

gen-op-cert() {
  if [ -e "node.cert" ]; then
    echo "Operational certificate already generated. You can exec into container and check under '$WORK_DIR' folder"
    exit 0
  fi

  slotsPerKESPeriod=$(cat ../files/shelley-genesis.json | jq -r '.slotsPerKESPeriod')
  echo slotsPerKESPeriod: ${slotsPerKESPeriod}

  slotNo=$(cardano-cli $ERA query tip $(get_network) | jq -r '.slot')
  echo slotNo: ${slotNo}

  startKesPeriod=$((${slotNo} / ${slotsPerKESPeriod}))
  echo startKesPeriod: ${startKesPeriod}

  cardano-cli $ERA node issue-op-cert \
      --kes-verification-key-file kes.vkey \
      --cold-signing-key-file cold.skey \
      --operational-certificate-issue-counter cold.counter \
      --kes-period ${startKesPeriod} \
      --out-file node.cert
    
  echo "Operational certificate generated successfully, it is saved under '$WORK_DIR' inside container."
}

balance() {
  if [ ! -e "payment.addr" ]; then
    echo "Wallet keys not present, you need to generate them first"
    exit 0
  fi

  addr=$(cat payment.addr)
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))
  currentBalance=$(echo $bal | jq -r .[].value.lovelace)
  keys=$(echo $bal | jq -r 'keys[]')

  echo "Balance for '$addr': ${currentBalance:-0} lovelace"
  echo -e "${Green}utxos below${Color_Off}"
  echo $keys
  echo 
  echo "You can topup the address if needed using the address hash shown"
}

build-sign-stake-reg-cert() {
  if [ ! -e "stake.vkey" ]; then
    echo "Wallet keys not present, you need to generate them first"
    exit 0
  fi

  if [ -e "tx.signed" ]; then
    echo "Stake address certificate already generated and saved to '$WORK_DIR/stake.cert' with transaction at '$WORK_DIR/tx.signed'"
    exit 0
  fi

  # Check balance
  addr=$(cat payment.addr)
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))
  currentBalance=$(echo $bal | jq -r .[].value.lovelace)
  echo currentBalance: $currentBalance

  # Get protocol.json
  cardano-cli $ERA query protocol-parameters $(get_network) --out-file protocol.json
  
  stakeAddressDeposit=$(cat protocol.json | jq -r '.stakeAddressDeposit')
  echo stakeAddressDeposit: $stakeAddressDeposit

  # tx-in
  txIn=$(echo $bal | jq -r 'keys[0]')
  echo txIn: $txIn

  # invalid-hereafter
  currentSlot=$(cardano-cli query tip $(get_network) | jq -r '.slot')
  echo Current Slot: $currentSlot

  # generate certificate
  cardano-cli $ERA stake-address registration-certificate \
    --stake-verification-key-file stake.vkey \
    --out-file stake.cert \
    --key-reg-deposit-amt $stakeAddressDeposit
  echo "Stake address certificate generated and saved to '$WORK_DIR/stake.cert'"

  # estimate fee
  fee=$(cardano-cli $ERA transaction build \
      --tx-in ${txIn} \
      --tx-out $(cat payment.addr)+1000000 \
      --change-address $(cat payment.addr) \
      $(get_network) \
      --certificate-file stake.cert \
      --invalid-hereafter $(( ${currentSlot} + 1000)) \
      --witness-override 2 \
      --out-file tx.draft)
  echo $fee

  # Parse transaction and get fee as number
  cardano-cli debug transaction view --tx-file tx.draft > tx.json
  feeNum=$(jq '.fee | gsub("[^0-9]"; "") | tonumber' tx.json)

  # Calculate change
  txOut=$(($currentBalance - $stakeAddressDeposit - $feeNum))
  echo "Change (currentBalance - stakeAddressDeposit - feeNum): ${txOut}"

  # Build the transaction
  cardano-cli $ERA transaction build-raw \
      --tx-in ${txIn} \
      --tx-out $(cat payment.addr)+${txOut} \
      --invalid-hereafter $((${currentSlot} + 1000)) \
      --fee ${feeNum} \
      --certificate-file stake.cert \
      --out-file tx.raw

  # Sign and Submit the transaction
  cardano-cli $ERA transaction sign \
      --tx-body-file tx.raw \
      --signing-key-file payment.skey \
      --signing-key-file stake.skey \
      $(get_network) \
      --out-file tx.signed
  
  echo "Transaction to submit certificate created and signed, saved at '$WORK_DIR/tx.signed'"
}

submit-stake-reg-cert() {
  cardano-cli $ERA transaction submit \
    --tx-file tx.signed \
    $(get_network)
}

pool-data() {
  if [ -e "poolMetaData.json" ]; then
    echo "'$WORK_DIR/poolMetaData.json' already exists"
    exit 0
  fi

  read -r -p "Enter Pool Name: " pool_name
  read -r -p "Enter Pool Descrption: " pool_desc
  read -r -p "Enter Pool Ticker (3-5 characters only): " pool_ticker
  read -r -p "Enter Pool Homepage http:// or https://: " pool_url

  # Create JSON file with your metadata
  cat > poolMetaData.json <<< "{\"name\": \"$pool_name\", \"description\": \"$pool_desc\", \"ticker\": \"$pool_ticker\", \"homepage\": \"$pool_url\"}"

  # Calculate the hash of your metadata file
  cardano-cli $ERA stake-pool metadata-hash \
      --pool-metadata-file poolMetaData.json > poolMetaDataHash.txt

  # Copy to source folder
  cp poolMetaData.json ../source/poolMetaData.json
  echo -e "${Green}You need to upload the file created in cardano-docker directory to a publicly reachable URL${Color_Off}"
}

build-sign-pool-cert() {
  if [ -e "txp.signed" ]; then
    echo "'$WORK_DIR/txp.signed' already generated and signed"
    exit 0
  fi
  
  read -r -p "Enter URL for poolMetaData.json (Max 64 characters, no redirect): " metadata_url

  # Get hash from online file
  hash0=$(cat poolMetaDataHash.txt)
  hash1=$(cardano-cli $ERA stake-pool metadata-hash --pool-metadata-file <(curl -s -L $metadata_url))

  if [ "$hash0" != "$hash1" ]; then
    cp poolMetaData.json ../source/poolMetaData.json
    echo "The hash for poolMetaData.json from remote does not match local. Re upload it again."
    echo "It has been copied to source folder ie cardano-docker folder"
    exit 0
  fi

  # Find the minimum pool cost:
  cardano-cli $ERA query protocol-parameters \
      $(get_network)  \
      --out-file protocol.json

  read -r -p "Enter relay node URL: " relay_url

  minPoolCost=$(cat protocol.json | jq -r .minPoolCost)
  echo minPoolCost: ${minPoolCost}

  stakePoolDeposit=$(cat protocol.json | jq -r '.stakePoolDeposit')
  echo $stakePoolDeposit

  # Generate the stake pool registration certificate
  cardano-cli $ERA stake-pool registration-certificate \
      --cold-verification-key-file cold.vkey \
      --vrf-verification-key-file vrf.vkey \
      --pool-pledge 100000000 \
      --pool-cost 340000000 \
      --pool-margin 0.01 \
      --pool-reward-account-verification-key-file stake.vkey \
      --pool-owner-stake-verification-key-file stake.vkey \
      $(get_network) \
      --single-host-pool-relay $relay_url  \
      --pool-relay-port 6000 \
      --metadata-url $metadata_url \
      --metadata-hash $(cat poolMetaDataHash.txt) \
      --out-file pool.cert

  # Create a delegation certificate pledge
  cardano-cli $ERA stake-address stake-delegation-certificate \
      --stake-verification-key-file stake.vkey \
      --cold-verification-key-file cold.vkey \
      --out-file deleg.cert

  # Check balance
  addr=$(cat payment.addr)
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))
  currentBalance=$(echo $bal | jq -r .[].value.lovelace)
  echo currentBalance: $currentBalance

  # tx-in
  txIn=$(echo $bal | jq -r 'keys[0]')
  echo txIn: $txIn

  # invalid-hereafter
  currentSlot=$(cardano-cli query tip $(get_network) | jq -r '.slot')
  echo Current Slot: $currentSlot

  # Estimate fee
  feeNum=1000000 # 1 ADA
  fee=$(cardano-cli $ERA transaction build \
      --tx-in ${txIn} \
      --tx-out $(cat payment.addr)+${feeNum} \
      --change-address $(cat payment.addr) \
      $(get_network) \
      --certificate-file pool.cert \
      --certificate-file deleg.cert \
      --invalid-hereafter $(( ${currentSlot} + 1000)) \
      --witness-override 2 \
      --out-file txp.draft)
  echo $fee

  # Parse transaction and get fee as number
  cardano-cli debug transaction view --tx-file txp.draft > txp.json
  feeNum=$(jq '.fee | gsub("[^0-9]"; "") | tonumber' txp.json)

  txOut=$(($currentBalance - $stakePoolDeposit - $feeNum))
  echo Change: ${txOut}

  # Build transaction
  cardano-cli $ERA transaction build-raw \
      --tx-in ${txIn} \
      --tx-out $(cat payment.addr)+${txOut} \
      --invalid-hereafter $((${currentSlot} + 1000)) \
      --fee $feeNum \
      --certificate-file pool.cert \
      --certificate-file deleg.cert \
      --out-file txp.raw

  # Sign
  cardano-cli $ERA transaction sign \
      --tx-body-file txp.raw \
      --signing-key-file payment.skey \
      --signing-key-file cold.skey \
      --signing-key-file stake.skey \
      $(get_network) \
      --out-file txp.signed
}

submit-pool-cert() {
  cardano-cli $ERA transaction submit \
    --tx-file txp.signed \
    $(get_network)
}

details(){
  cardano-cli $ERA stake-pool id \
    --cold-verification-key-file cold.vkey \
    --output-format hex > stakepoolid.txt

  id=$(cat stakepoolid.txt)
  echo "Stake Pool ID: $id"
  echo
  
  echo "Stake pool details"
  cardano-cli $ERA query stake-snapshot \
    --stake-pool-id $(cat stakepoolid.txt) \
    $(get_network)
}

help() {
  echo "usage: ${__me} [-h|--help] <command>"
  echo
  echo "This script is designed to help you setup your stake pool. The following steps are taken to start a stakepool"
  echo
  echo "1.  Generate wallet keys"
  echo "2.  Generate Block Producer Keys"
  echo "3.  Generate operational certificate"
  echo -e "${Green}4.  Restart relay node with keys generated to be a block producer node. Just uncomment the keys from .env${Color_Off}"
  echo "5.  To-up your address."
  echo "6.  Build & sign stake reg certificate & transaction"
  echo "7.  Submit stake registration certificate transaction"
  echo "8.  Create poolMetaData.json and upload to a server reachable via GET http or https"
  echo "9.  Build & sign pool reg certificate & transaction"
  echo "10. Submit pool registration certificate transaction"
  echo
  echo "Which action command do you want?"
  echo -e "  ${Green}bash${Color_Off}"
  echo "    Exec into container folder with keys. You can view or copy them from there."
  echo -e "  ${Green}balance${Color_Off}"
  echo "    Check the balance of payment.addr"
  echo -e "  ${Green}gen-wallet${Color_Off}"
  echo "    Generate wallet keys 'payment.skey', 'payment.vkey' 'payment.addr', 'stake.skey', 'stake.vkey'"
  echo "    and 'stake.addr'. Will also check that keys dont exist to avoid overwrite"
  echo -e "  ${Green}gen-block-producer${Color_Off}"
  echo "    Generate block producer keys 'cold.skey', 'cold.vkey' 'cold.counter', 'kes.skey', 'kes.vkey'"
  echo "    'vrf.skey', and 'vrf.vkey'. Will also check that keys dont exist to avoid overwrite"
  echo -e "  ${Green}gen-op-cert${Color_Off}"
  echo "    Generate operational certificate, no overwrite"
  echo -e "  ${Green}build-sign-stake-reg-cert${Color_Off}"
  echo "    Create stake registration certificate and sign it"
  echo -e "  ${Green}submit-stake-reg-cert${Color_Off}"
  echo "    Submit stake registration certificate to the blockchain"
  echo -e "  ${Green}pool-data${Color_Off}"
  echo "    Generate poolMetaData.json. You need to upload it to a server after generation"
  echo -e "  ${Green}build-sign-pool-cert${Color_Off}"
  echo "    Create pool registration certificate and sign it"
  echo -e "  ${Green}submit-pool-cert${Color_Off}"
  echo "    Submit pool registration certificate to the blockchain"
  echo -e "  ${Green}details${Color_Off}"
  echo "    Get details about stake pool"
}

__me="./ethd stakepool"
if [[ "$#" -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  help
  exit 0
fi

__command="$1"
case "$__command" in
  help|bash|balance|gen-wallet|gen-block-producer|gen-op-cert|build-sign-stake-reg-cert|submit-stake-reg-cert|pool-data|build-sign-pool-cert|submit-pool-cert|details)
    $__command "$@";;
  *)
    echo "Unrecognized command $__command"
    help
    ;;
esac

