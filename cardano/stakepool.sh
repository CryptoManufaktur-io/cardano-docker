#!/usr/bin/env bash
set -Eeuo pipefail
WORK_DIR=/runtime/keys
cd $WORK_DIR

Color_Off='\033[0m'       # Text Reset
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Blue='\033[0;34m'         # Blue

bash(){
    /bin/bash
}

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

gen-payment-keys() {
  if [ -e "payment/payment.skey" ]; then
    echo -e "${Red}Error!! Payment keys already generated. Check under keys/payment folder${Color_Off}"
    exit 0
  fi

  # Generating Payment Keys
  mkdir -p payment block-producer
  cardano-cli $ERA address key-gen \
      --verification-key-file payment/payment.vkey \
      --signing-key-file payment/payment.skey

  # Generating Payment address
  cardano-cli $ERA address build \
      --payment-verification-key-file payment/payment.vkey \
      --out-file block-producer/payment.addr \
      $(get_network)
  
  echo -e "${Green}Payment keys generated successfully, they are saved under keys/payment folder.${Color_Off}"
}

gen-stake-keys() {
  if [ -e "stake/stake.skey" ]; then
    echo -e "${Red}Error!! Stake keys already generated. Check under keys/stake folder${Color_Off}"
    exit 0
  fi

  # Generating Stake Keys
  mkdir -p stake block-producer
  cardano-cli $ERA stake-address key-gen \
      --verification-key-file stake/stake.vkey \
      --signing-key-file stake/stake.skey

  # Create your stake address from the stake address verification key
  cardano-cli $ERA stake-address build \
      --stake-verification-key-file stake/stake.vkey \
      --out-file block-producer/stake.addr \
      $(get_network)
  
  # generate certificate
  echo "Provide stakeAddressDeposit (You can get it by executing the command below on a running node)"
  echo ""
  echo -e "${Blue}./ethd cmd exec cardano-node cardano-cli $ERA query protocol-parameters $(get_network) | jq -r '.stakeAddressDeposit'${Color_Off}"
  echo ""
  read -r -p "Enter stakeAddressDeposit: " stakeAddressDeposit

  cardano-cli $ERA stake-address registration-certificate \
    --stake-verification-key-file stake/stake.vkey \
    --out-file block-producer/stake.cert \
    --key-reg-deposit-amt $stakeAddressDeposit
  
  echo -e "${Green}Stake keys and certificated generated successfully, they are saved under keys/stake folder, certificate saved under keys/block-producer folder.${Color_Off}"
}

gen-cold-keys() {
  if [ -e "cold-keys/cold.skey" ]; then
    echo -e "${Red}Error!! Block producer cold keys already generated, check under keys/cold-keys folder${Color_Off}"
    exit 0
  fi

  # Generating Cold Keys
  mkdir -p cold-keys block-producer
  cardano-cli $ERA node key-gen \
      --cold-verification-key-file cold-keys/cold.vkey \
      --cold-signing-key-file cold-keys/cold.skey \
      --operational-certificate-issue-counter cold-keys/cold.counter

  # Generating VRF Keys
  cardano-cli $ERA node key-gen-VRF \
      --verification-key-file vrf.vkey \
      --signing-key-file block-producer/vrf.skey
  chmod 400 block-producer/vrf.skey

  echo -e "${Green}Block producer cold keys generated successfully, they are saved under keys/cold-keys folder. vrf.skey is under keys/block-producer folder.${Color_Off}"
}

gen-op-cert() {
  if [ ! -e "cold-keys/cold.skey" ]; then
    echo -e "${Red}Error!! Could not find cold.skey, generate it if not generated with ./ethd stakepool gen-cold-keys${Color_Off}"
    exit 0
  fi

  if [ -e "block-producer/node.cert" ]; then
    echo -e "${Red}READ CAREFULLY${Color_Off}"
    read -r -p "Operational certificate exists in keys/block-producer folder, do you want to replace (only yes is accepted as input)? " do_replace

    if [[ "$do_replace" == "yes" ]]; then
      rm block-producer/node.cert
    else
      echo "Operation aborted"
      exit 0
    fi
  fi

  # Get slotNo
  echo "Provide slotNo (You can get it by executing the command below on a running node)"
  echo ""
  echo -e "${Blue}./ethd tip | jq -r '.slot'${Color_Off}"
  echo ""
  read -r -p "Enter slotNo: " slotNo
  echo slotNo: ${slotNo}

  # Create folder
  mkdir -p block-producer

  # Generating KES Keys
  cardano-cli $ERA node key-gen-KES \
      --verification-key-file kes.vkey \
      --signing-key-file block-producer/kes.skey

  SHELLY_JSON=$(curl -s https://book.world.dev.cardano.org/environments/${NETWORK}/shelley-genesis.json)
  slotsPerKESPeriod=$(echo $SHELLY_JSON | jq -r '.slotsPerKESPeriod')
  echo slotsPerKESPeriod: ${slotsPerKESPeriod}

  startKesPeriod=$((${slotNo} / ${slotsPerKESPeriod}))
  echo startKesPeriod: ${startKesPeriod}

  cardano-cli $ERA node issue-op-cert \
      --kes-verification-key-file kes.vkey \
      --cold-signing-key-file cold-keys/cold.skey \
      --operational-certificate-issue-counter cold-keys/cold.counter \
      --kes-period ${startKesPeriod} \
      --out-file block-producer/node.cert
    
  echo -e "${Green}Operational certificate generated successfully, it is saved under keys/block-producer folder. You can now copy everything on keys/block-producer folder to your node and restart it.${Color_Off}"
}

balance() {
  if [ ! -e "block-producer/payment.addr" ]; then
    echo -e "${Red}Error!! Payment address not present, you need payment.addr inside keys/block-producer folder${Color_Off}"
    exit 0
  fi

  addr=$(cat block-producer/payment.addr)
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))
  currentBalance=$(echo $bal | jq -r .[].value.lovelace)
  keys=$(echo $bal | jq -r 'keys[]')

  echo "Balance for '$addr': ${currentBalance:-0} lovelace"
  echo -e "${Blue}utxos${Color_Off}"
  echo $keys
  echo 
  echo "You can topup the address if needed using the address hash shown"
}

gen-raw-stake-cert() {
  if [ -e "tx.raw" ]; then
    echo -e "${Red}Error!! Raw transaction to submit stake certificate already generated and saved to 'keys/tx.raw'${Red}"
    exit 0
  fi

  # Check balance
  addr=$(cat block-producer/payment.addr)
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))
  currentBalance=$(echo $bal | jq -r .[].value.lovelace)
  echo currentBalance: $currentBalance
  
  # Get stakeAddressDeposit
  PROTOCOL_JSON=$(cardano-cli $ERA query protocol-parameters $(get_network))
  stakeAddressDeposit=$(echo $PROTOCOL_JSON | jq -r '.stakeAddressDeposit')
  echo stakeAddressDeposit: $stakeAddressDeposit

  # tx-in
  txIn=$(echo $bal | jq -r 'keys[0]')
  echo txIn: $txIn

  # invalid-hereafter
  currentSlot=$(cardano-cli query tip $(get_network) | jq -r '.slot')
  echo Current Slot: $currentSlot

  # estimate fee
  fee=$(cardano-cli $ERA transaction build \
      --tx-in ${txIn} \
      --tx-out ${addr}+1000000 \
      --change-address ${addr} \
      $(get_network) \
      --certificate-file block-producer/stake.cert \
      --invalid-hereafter $(( ${currentSlot} + 1000)) \
      --witness-override 2 \
      --out-file tx.draft)
  echo $fee

  # Parse transaction and get fee as number
  feeNum=$(cardano-cli debug transaction view --tx-file tx.draft | jq '.fee | gsub("[^0-9]"; "") | tonumber')

  # Calculate change
  txOut=$(($currentBalance - $stakeAddressDeposit - $feeNum))
  echo "Change (currentBalance - stakeAddressDeposit - feeNum): ${txOut}"

  # Build the transaction
  cardano-cli $ERA transaction build-raw \
      --tx-in ${txIn} \
      --tx-out ${addr}+${txOut} \
      --invalid-hereafter $((${currentSlot} + 1000)) \
      --fee ${feeNum} \
      --certificate-file block-producer/stake.cert \
      --out-file tx.raw
  
  echo "Raw transaction to submit stake certificate generated, saved at 'keys/tx.raw'"
}

sign-raw-stake-cert(){
  if [ -e "tx.signed" ]; then
    echo -e "${Red}Error!! Signed transaction to submit stake certificate already present and saved to 'keys/tx.signed'${Red}"
    exit 0
  fi

  # Sign and Submit the transaction
  cardano-cli $ERA transaction sign \
      --tx-body-file tx.raw \
      --signing-key-file payment/payment.skey \
      --signing-key-file stake/stake.skey \
      $(get_network) \
      --out-file tx.signed
}

submit-stake-cert() {
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
  echo -e "${Blue}You need to upload the file created in cardano-docker directory to a publicly reachable URL${Color_Off}"
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
  PROTOCOL_JSON=$(cardano-cli $ERA query protocol-parameters $(get_network))

  minPoolCost=$(echo $PROTOCOL_JSON | jq -r .minPoolCost)
  echo minPoolCost: ${minPoolCost}

  stakePoolDeposit=$(echo $PROTOCOL_JSON | jq -r '.stakePoolDeposit')
  echo $stakePoolDeposit

  # Generate the stake pool registration certificate
  read -r -p "Enter relay node URL: " relay_url
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
  echo "Which action command do you want?"

  echo -e "  ${Blue}bash${Color_Off}"
  echo "    Mount all volumes and exec into container."

  echo -e "  ${Blue}balance${Color_Off}"
  echo "    Check the balance of payment.addr"

  echo -e "  ${Blue}gen-payment-keys${Color_Off}"
  echo "    Generate 'payment.skey', 'payment.vkey' and 'payment.addr', will ask before overwrite"

  echo -e "  ${Blue}gen-stake-keys${Color_Off}"
  echo "    Generate 'stake.skey', 'stake.vkey' and 'stake.addr', will ask before overwrite"

  echo -e "  ${Blue}gen-cold-keys${Color_Off}"
  echo "    Generate block producer 'cold.skey', 'cold.vkey' 'cold.counter', 'vrf.skey', and 'vrf.vkey'. Will ask before overwrite"

  echo -e "  ${Blue}gen-op-cert${Color_Off}"
  echo "    Generate or rotate 'kes.vkey', 'kes.vkey' and 'node.cert', will confirm before overwrite"

  echo -e "  ${Blue}gen-raw-stake-cert${Color_Off}"
  echo "    Create raw stake registration certificate transaction tx.raw"

  echo -e "  ${Blue}submit-stake-cert${Color_Off}"
  echo "    Submit stake registration certificate to the blockchain"

  echo -e "  ${Blue}pool-data${Color_Off}"
  echo "    Generate poolMetaData.json. You need to upload it to a server after generation"

  echo -e "  ${Blue}build-sign-pool-cert${Color_Off}"
  echo "    Create pool registration certificate and sign it"

  echo -e "  ${Blue}submit-pool-cert${Color_Off}"
  echo "    Submit pool registration certificate to the blockchain"

  echo -e "  ${Blue}details${Color_Off}"
  echo "    Get details about stake pool"
}

__me="./ethd stakepool"
if [[ "$#" -eq 0 || "$1" == "-h" || "$1" == "--help" ]]; then
  help
  exit 0
fi

__command="$1"
case "$__command" in
  help|bash|balance|gen-payment-keys|gen-stake-keys|gen-cold-keys|gen-op-cert|gen-raw-stake-cert|submit-stake-cert|pool-data|build-sign-pool-cert|submit-pool-cert|details)
    $__command "$@";;
  *)
    echo "Unrecognized command $__command"
    help
    ;;
esac

