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

get_current_balance() {
  # Check balance
  addr="$(cat block-producer/payment.addr)"
  bal=$(cardano-cli $ERA query utxo --address $addr --output-json $(get_network))

  # Extract all lovelace values and calculate total balance
  utxoBalances=$(echo $bal | jq -r .[].value.lovelace)
  totalBalance=$(echo $utxoBalances | awk '{sum += $1} END {print sum}')
  
  # Count the number of UTXOs
  numUTXOs=$(echo "$utxoBalances" | wc -l)

  # Format totalBalance as a number without scientific notation
  formattedTotalBalance=$(printf "%.0f" "$totalBalance")

  # Loop through UTXOs and build the --tx-in string
  txInString=""
  while IFS="," read -r txid txix; do
    txInString+="--tx-in ${txid}#${txix} "
  done < <(echo "$bal" | jq -r 'keys[] as $k | "\($k | split("#")[0]),\($k | split("#")[1])"')

  # Output as a single line with a delimiter
  echo "$numUTXOs|$formattedTotalBalance|$txInString"
}

bash(){
    /bin/bash
}

balance() {
  if [ ! -e "block-producer/payment.addr" ]; then
    echo -e "${Red}Error!! block-producer/payment.addr not present${Color_Off}"
    exit 0
  fi

  addr="$(cat block-producer/payment.addr)"
  IFS="|" read -r numUTXOs totalBalance txInString <<< "$(get_current_balance)"
  echo "Balance for '$addr'"
  echo "Number of UTXOs: $numUTXOs"
  echo "Total Balance: $totalBalance lovelace"
  echo 
  echo "You can topup the address if needed using the address hash shown"
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

  # Generating Payment address
  cardano-cli $ERA address build \
      --payment-verification-key-file payment/payment.vkey \
      --stake-verification-key-file stake/stake.vkey \
      --out-file block-producer/payment.addr \
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

  # Generate stakepoolid.txt
  cardano-cli $ERA stake-pool id \
    --cold-verification-key-file cold-keys/cold.vkey \
    --output-format hex > block-producer/stakepoolid.txt

  # Generating VRF Keys
  cardano-cli $ERA node key-gen-VRF \
      --verification-key-file block-producer/vrf.vkey \
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
      --verification-key-file block-producer/kes.vkey \
      --signing-key-file block-producer/kes.skey

  # Get slotNo
  echo "Provide slotsPerKESPeriod (You can get it by executing the command below on a running node)"
  echo ""
  echo -e "${Blue}./ethd cmd exec cardano-node cat /runtime/files/shelley-genesis.json | jq -r '.slotsPerKESPeriod'${Color_Off}"
  echo ""
  read -r -p "Enter slotsPerKESPeriod: " slotsPerKESPeriod
  echo slotsPerKESPeriod: ${slotsPerKESPeriod}

  startKesPeriod=$((${slotNo} / ${slotsPerKESPeriod}))
  echo startKesPeriod: ${startKesPeriod}

  cardano-cli $ERA node issue-op-cert \
      --kes-verification-key-file block-producer/kes.vkey \
      --cold-signing-key-file cold-keys/cold.skey \
      --operational-certificate-issue-counter cold-keys/cold.counter \
      --kes-period ${startKesPeriod} \
      --out-file block-producer/node.cert
    
  echo -e "${Green}Operational certificate generated successfully, it is saved under keys/block-producer folder. You can now copy everything on keys/block-producer folder to your node and restart it.${Color_Off}"
}

gen-tran-stake-cert() {
  calculateDepositFee=${2:-yes}

  if [ -e "block-producer/tx.raw" ]; then
    echo -e "${Red}Error!! Raw transaction to submit stake certificate already generated and saved to keys/block-producer/tx.raw${Color_Off}"
    exit 0
  fi

  # Check balance
  addr="$(cat block-producer/payment.addr)"
  IFS="|" read -r numUTXOs totalBalance txInString <<< "$(get_current_balance)"
  echo "Number of UTXOs: $numUTXOs"
  echo "Total Balance: $totalBalance"
  echo "UTXOs: $txInString"
  
  if [[ "$calculateDepositFee" == "yes" ]]; then
    # Get stakeAddressDeposit
    PROTOCOL_JSON=$(cardano-cli $ERA query protocol-parameters $(get_network))
    stakeAddressDeposit=$(echo $PROTOCOL_JSON | jq -r '.stakeAddressDeposit')
    echo stakeAddressDeposit: $stakeAddressDeposit
  else
    echo "No need to pay deposit again"
    stakeAddressDeposit=0
  fi

  # invalid-hereafter
  currentSlot=$(cardano-cli query tip $(get_network) | jq -r '.slot')
  echo Current Slot: $currentSlot

  # estimate fee
  fee=$(cardano-cli $ERA transaction build \
      ${txInString} \
      --tx-out ${addr}+1000000 \
      --change-address ${addr} \
      $(get_network) \
      --certificate-file block-producer/stake.cert \
      --invalid-hereafter $(( ${currentSlot} + 1000)) \
      --witness-override 2 \
      --out-file block-producer/tx.draft)
  echo $fee

  # Parse transaction and get fee as number
  feeNum=$(cardano-cli debug transaction view --tx-file block-producer/tx.draft | jq '.fee | gsub("[^0-9]"; "") | tonumber')

  # Calculate change
  txOut=$(($totalBalance - $stakeAddressDeposit - $feeNum))
  echo "Change (totalBalance[$totalBalance] - stakeAddressDeposit[$stakeAddressDeposit] - feeNum[$feeNum]): ${txOut}"

  # Build the transaction
  cardano-cli $ERA transaction build-raw \
      ${txInString} \
      --tx-out ${addr}+${txOut} \
      --invalid-hereafter $((${currentSlot} + 1000)) \
      --fee ${feeNum} \
      --certificate-file block-producer/stake.cert \
      --out-file block-producer/tx.raw
  
  echo -e "${Green}Raw transaction to submit stake certificate generated, saved at keys/block-producer/tx.raw${Color_Off}"
}

sign-tran-stake-cert(){
  if [ -e "block-producer/tx.signed" ]; then
    echo -e "${Red}Error!! Signed transaction to submit stake certificate already present and saved to keys/block-producer/tx.signed${Color_Off}"
    exit 0
  fi

  # Sign and Submit the transaction
  cardano-cli $ERA transaction sign \
      --tx-body-file block-producer/tx.raw \
      --signing-key-file payment/payment.skey \
      --signing-key-file stake/stake.skey \
      $(get_network) \
      --out-file block-producer/tx.signed
  
  echo -e "${Green}Transaction to submit stake certificate signed, saved at keys/block-producer/tx.signed${Color_Off}"
}

submit-stake-tran() {
  cardano-cli $ERA transaction submit \
    --tx-file block-producer/tx.signed \
    $(get_network)
}

pool-data() {
  if [ -e "block-producer/poolMetaData.json" ]; then
    echo -e "${Red}Error!! keys/block-producer/poolMetaData.json already exists${Color_Off}"
    exit 0
  fi

  read -r -p "Enter Pool Name: " pool_name
  read -r -p "Enter Pool Descrption: " pool_desc
  read -r -p "Enter Pool Ticker (3-5 characters only, A-Z and 0-9 only): " pool_ticker
  read -r -p "Enter Pool Homepage http:// or https://: " pool_url

  # Create JSON file with your metadata
  cat > block-producer/poolMetaData.json <<< "{\"name\": \"$pool_name\", \"description\": \"$pool_desc\", \"ticker\": \"$pool_ticker\", \"homepage\": \"$pool_url\"}"

  # Calculate the hash of your metadata file
  cardano-cli $ERA stake-pool metadata-hash \
      --pool-metadata-file block-producer/poolMetaData.json > block-producer/poolMetaDataHash.txt

  echo -e "${Green}Done, You need to upload block-producer/poolMetaData.json to a publicly reachable URL${Color_Off}"
}

verify-pool-data(){
  read -r -p "Enter URL for poolMetaData.json (Max 64 characters, no redirect): " metadata_url

  # Get hash from online file
  hash0=$(cat block-producer/poolMetaDataHash.txt)
  hash1=$(cardano-cli $ERA stake-pool metadata-hash --pool-metadata-file <(curl -s -L $metadata_url))

  if [ "$hash0" != "$hash1" ]; then
    echo -e "${Red}Error!! The hash for block-producer/poolMetaData.json from remote does not match local. Re-upload or check it again.${Color_Off}"
    exit 0
  fi

  echo -e "${Green}Hash of remote poolMetaData.json matches local${Color_Off}"
}

gen-pool-cert() {
  if [ -e "block-producer/pool.cert" ]; then
    echo -e "${Red}READ CAREFULLY${Color_Off}"
    read -r -p "Pool certificate exists in keys/block-producer folder, do you want to replace (only yes is accepted as input)? " do_replace

    if [[ "$do_replace" == "yes" ]]; then
      rm block-producer/pool.cert
    else
      echo "Operation aborted"
      exit 0
    fi
  fi
  
  if [ ! -e "block-producer/poolMetaData.json" ]; then
    echo -e "${Red}Error!! keys/block-producer/poolMetaData.json does not exists${Color_Off}"
    exit 0
  fi

  read -r -p "Enter URL for poolMetaData.json (Max 64 characters, no redirect): " metadata_url
  
  # Relay URLs
  read -r -p "Enter relay node Public URLs (Space separated, no http part): " relay_urls
  relay_urls_all=""
  IFS=' ' read -r -a URLS <<< "$relay_urls"
  for url in "${URLS[@]}"
  do
      relay_urls_all=$(echo "$relay_urls_all --single-host-pool-relay $url --pool-relay-port 6000")
  done

  read -r -p "Enter pool pledge amount (ie 100000000): " pool_pledge
  read -r -p "Enter pool cost (ie 345000000): " pool_cost
  read -r -p "Enter pool margin % (ie 0.15 for 15%): " pool_margin

  # Generate the stake pool registration certificate
  cardano-cli $ERA stake-pool registration-certificate \
      --cold-verification-key-file cold-keys/cold.vkey \
      --vrf-verification-key-file block-producer/vrf.vkey \
      --pool-pledge $pool_pledge \
      --pool-cost $pool_cost \
      --pool-margin $pool_margin \
      --pool-reward-account-verification-key-file stake/stake.vkey \
      --pool-owner-stake-verification-key-file stake/stake.vkey \
      $(get_network) \
      $relay_urls_all  \
      --metadata-url $metadata_url \
      --metadata-hash $(cat block-producer/poolMetaDataHash.txt) \
      --out-file block-producer/pool.cert
  
  echo -e "${Green}block-producer/pool.cert generated successfully${Color_Off}"
}

gen-deleg-cert() {
  if [ -e "block-producer/deleg.cert" ]; then
    echo -e "${Red}READ CAREFULLY${Color_Off}"
    read -r -p "Delegation certificate exists in keys/block-producer folder, do you want to replace (only yes is accepted as input)? " do_replace

    if [[ "$do_replace" == "yes" ]]; then
      rm block-producer/deleg.cert
    else
      echo "Operation aborted"
      exit 0
    fi
  fi

  # Create a delegation certificate pledge
  cardano-cli $ERA stake-address stake-delegation-certificate \
      --stake-verification-key-file stake/stake.vkey \
      --cold-verification-key-file cold-keys/cold.vkey \
      --out-file block-producer/deleg.cert

  echo -e "${Green}block-producer/deleg.cert generated successfully${Color_Off}"
}

gen-raw-pool-tran() {
  calculateDepositFee=${2:-yes}

  if [ -e "block-producer/txp.raw" ]; then
    echo -e "${Red}READ CAREFULLY${Color_Off}"
    read -r -p "Raw pool transaction exists in keys/block-producer folder, do you want to replace (only yes is accepted as input)? " do_replace

    if [[ "$do_replace" == "yes" ]]; then
      rm block-producer/txp.raw
    else
      echo "Operation aborted"
      exit 0
    fi
  fi
  
  if [[ "$calculateDepositFee" == "yes" ]]; then
    # Get stakePoolDeposit
    PROTOCOL_JSON=$(cardano-cli $ERA query protocol-parameters $(get_network))
    stakePoolDeposit=$(echo $PROTOCOL_JSON | jq -r '.stakePoolDeposit')
    echo $stakePoolDeposit
  else
    echo "No need to pay deposit again"
    stakePoolDeposit=0
  fi

  # Check balance
  addr="$(cat block-producer/payment.addr)"
  IFS="|" read -r numUTXOs totalBalance txInString <<< "$(get_current_balance)"
  echo "Number of UTXOs: $numUTXOs"
  echo "Total Balance: $totalBalance"
  echo "UTXOs: $txInString"

  # invalid-hereafter
  currentSlot=$(cardano-cli query tip $(get_network) | jq -r '.slot')
  echo Current Slot: $currentSlot

  # Estimate fee
  feeNum=1000000 # 1 ADA
  fee=$(cardano-cli $ERA transaction build \
      ${txInString} \
      --tx-out ${addr}+${totalBalance} \
      --change-address ${addr} \
      $(get_network) \
      --certificate-file block-producer/pool.cert \
      --certificate-file block-producer/deleg.cert \
      --invalid-hereafter $(( ${currentSlot} + 10000)) \
      --witness-override 2 \
      --out-file block-producer/txp.draft)
  echo $fee

  # Parse transaction and get fee as number
  feeNum=$(cardano-cli debug transaction view --tx-file block-producer/txp.draft | jq '.fee | gsub("[^0-9]"; "") | tonumber')

  txOut=$(($totalBalance - $stakePoolDeposit - $feeNum))
  echo "Change (totalBalance[$totalBalance] - stakeAddressDeposit[$stakePoolDeposit] - feeNum[$feeNum]): ${txOut}"

  # Build transaction
  cardano-cli $ERA transaction build-raw \
      ${txInString} \
      --tx-out ${addr}+${txOut} \
      --invalid-hereafter $(( ${currentSlot} + 10000)) \
      --fee $feeNum \
      --certificate-file block-producer/pool.cert \
      --certificate-file block-producer/deleg.cert \
      --out-file block-producer/txp.raw

  echo -e "${Green}block-producer/txp.raw generated successfully${Color_Off}"
}

sign-raw-pool-tran() {
  if [ -e "block-producer/txp.signed" ]; then
    echo -e "${Red}READ CAREFULLY${Color_Off}"
    read -r -p "Signed pool transaction exists in keys/block-producer folder, do you want to replace (only yes is accepted as input)? " do_replace

    if [[ "$do_replace" == "yes" ]]; then
      rm block-producer/txp.signed
    else
      echo "Operation aborted"
      exit 0
    fi
  fi

  # Sign
  cardano-cli $ERA transaction sign \
      --tx-body-file block-producer/txp.raw \
      --signing-key-file payment/payment.skey \
      --signing-key-file cold-keys/cold.skey \
      --signing-key-file stake/stake.skey \
      $(get_network) \
      --out-file block-producer/txp.signed
  
  echo -e "${Green}block-producer/txp.signed generated successfully${Color_Off}"
}

submit-pool-tran() {
  cardano-cli $ERA transaction submit \
    --tx-file block-producer/txp.signed \
    $(get_network)
}

details(){
  id=$(cat block-producer/stakepoolid.txt)
  echo "Stake Pool ID: $id"
  echo
  
  echo "Stake pool details"
  cardano-cli $ERA query stake-snapshot \
    --stake-pool-id ${id} \
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

  echo -e "  ${Blue}gen-tran-stake-cert${Color_Off}"
  echo "    Create raw stake registration certificate transaction tx.raw"

  echo -e "  ${Blue}sign-tran-stake-cert${Color_Off}"
  echo "    Sign raw stake registration certificate transaction and generate tx.signed"

  echo -e "  ${Blue}submit-stake-tran${Color_Off}"
  echo "    Submit stake registration certificate transaction to the blockchain"

  echo -e "  ${Blue}pool-data${Color_Off}"
  echo "    Generate poolMetaData.json. You need to upload it to a server after generation"

  echo -e "  ${Blue}verify-pool-data${Color_Off}"
  echo "    Verify remote poolMetaData.json hash with local"

  echo -e "  ${Blue}gen-pool-cert${Color_Off}"
  echo "    Create pool registration certificate"

  echo -e "  ${Blue}gen-deleg-cert${Color_Off}"
  echo "    Create delegation certificate to pledge stake"

  echo -e "  ${Blue}gen-raw-pool-tran${Color_Off}"
  echo "    Generate transaction to submit pool and delegation certificates"

  echo -e "  ${Blue}sign-raw-pool-tran${Color_Off}"
  echo "    Sign transaction to submit pool and delegation certificates"

  echo -e "  ${Blue}submit-pool-tran${Color_Off}"
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
  help|bash|balance|gen-payment-keys|gen-stake-keys|gen-cold-keys|gen-op-cert|gen-tran-stake-cert|sign-tran-stake-cert|submit-stake-tran|pool-data|verify-pool-data|gen-pool-cert|gen-deleg-cert|gen-raw-pool-tran|sign-raw-pool-tran|submit-pool-tran|details)
    $__command "$@";;
  *)
    echo "Unrecognized command $__command"
    help
    ;;
esac

