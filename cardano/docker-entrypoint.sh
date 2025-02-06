#!/bin/bash
set -eu

# ---------------------------- REGION CONFIGS ---------------------------
CONFIGS_DIR=/runtime/files

# Config file for block producer is different
EXTRA_BLOCK_PRODUCER_ARGS=""
if [[ "${NODE_TYPE}" == "block-producer" ]]; then
    curl -o ${CONFIGS_DIR}/config.json -J https://book.world.dev.cardano.org/environments/${NETWORK}/config-bp.json
    EXTRA_BLOCK_PRODUCER_ARGS="--shelley-kes-key $KES --shelley-vrf-key $VRF --shelley-operational-certificate $CERT"
else
    curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/config.json --output-dir ${CONFIGS_DIR}
fi

curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/db-sync-config.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/submit-api-config.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/topology.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/byron-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/shelley-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/alonzo-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/conway-genesis.json --output-dir ${CONFIGS_DIR}

# Update config.json
json_data=$(cat $CONFIGS_DIR/config.json)
IFS=',' read -r -a CONFIG_CHANGES <<< "$CONFIG_UPDATES"
for change in "${CONFIG_CHANGES[@]}"
do
    json_data=$(echo "$json_data" | jq "$change")
done
echo "$json_data" > $CONFIGS_DIR/config.json

# Update topology.json
topology_data=$(cat $CONFIGS_DIR/topology.json)
IFS=',' read -r -a TOPOLOGY_CHANGES <<< "$TOPOLOGY_ACCESS_POINTS"
loop_index=0
for url in "${TOPOLOGY_CHANGES[@]}"
do
    topology_data=$(echo "$topology_data" | jq ".localRoots[0].accessPoints[$loop_index].address = \"$url\"")
    topology_data=$(echo "$topology_data" | jq ".localRoots[0].accessPoints[$loop_index].port = 6000")

    if [[ "${NODE_TYPE}" == "block-producer" ]]; then
        topology_data=$(echo "$topology_data" | jq ".localRoots[0].accessPoints[$loop_index].name = \"Relay $loop_index\"")
    else
        topology_data=$(echo "$topology_data" | jq ".localRoots[0].accessPoints[$loop_index].name = \"Block producer Node\"")
    fi

    loop_index=$(expr $loop_index + 1)
done
if [[ "${NODE_TYPE}" == "block-producer" ]]; then
    topology_data=$(echo "$topology_data" | jq ".bootstrapPeers = null")
    topology_data=$(echo "$topology_data" | jq ".useLedgerAfterSlot = -1")
else
    topology_data=$(echo "$topology_data" | jq ".localRoots[0].comment = \"Do NOT advertise the block-producing node\"")
fi
topology_data=$(echo "$topology_data" | jq ".localRoots[0].trustable = true")
topology_data=$(echo "$topology_data" | jq ".localRoots[0].valency = $loop_index")
echo "$topology_data" > $CONFIGS_DIR/topology.json
# ---------------------------- END REGION CONFIGS ------------------------

# ---------------------------- REGION SNAPSHOT ---------------------------
# Check if DB_DIR exists and is empty, and if SNAPSHOT is set and not empty
if [[ -d "${DB_DIR}" && -z "$(ls -A ${DB_DIR})" ]] && [[ -n "${SNAPSHOT}" ]]; then
    mkdir -p /runtime/temp
    FILENAME="/runtime/temp/snapshot.tar.lz4"
    
    echo "Starting or resuming downloading snapshot from ${SNAPSHOT}..."
    wget -c -O "${FILENAME}" "${SNAPSHOT}" --progress=dot:giga
    file_checksum=$(sha256sum "$FILENAME" | awk '{print $1}' | tr '[:upper:]' '[:lower:]')
    expected_checksum=$(echo "${SNAPSHOT_CHECKSUM}" | tr '[:upper:]' '[:lower:]')

    # Check if the file was downloaded successfully
    if [[ "${file_checksum}" == "${expected_checksum}" ]]; then
        # Check if the extraction was successful
        if lz4 -dvc --no-sparse "${FILENAME}" | tar xv --strip-components=1 -C "${DB_DIR}"; then
            echo "Extraction for snapshot successful!"
            rm -rf /runtime/temp
        else
            echo "Error: Extraction for snapshot failed."
            rm -rf /runtime/temp
            exit 1
        fi
    else
        echo "Error: Failed to download snapshot file."
        rm -rf /runtime/temp
        exit 1
    fi
else
    echo "No snapshot provided or already synced"
fi
# ---------------------------- END REGION SNAPSHOT -----------------------

cardano-node run $NODE_EXTRA_ARGS \
    --config $CONFIG \
    --topology $TOPOLOGY \
    --socket-path $SOCKET \
    --database-path $DB_DIR \
    --host-addr $CNODE_HOST \
    --port $CNODE_PORT \
    $EXTRA_BLOCK_PRODUCER_ARGS
