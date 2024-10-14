#!/bin/bash
set -eu

# ---------------------------- REGION CONFIGS ---------------------------
CONFIGS_DIR=/runtime/files
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/config.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/db-sync-config.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/submit-api-config.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/topology.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/byron-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/shelley-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/alonzo-genesis.json --output-dir ${CONFIGS_DIR}
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/conway-genesis.json --output-dir ${CONFIGS_DIR}

# To Update config as needed; Load the JSON into a variable
json_data=$(cat $CONFIGS_DIR/config.json)

# Modify the values with jq as needed
IFS=',' read -r -a CONFIG_CHANGES <<< "$CONFIG_UPDATES"
for change in "${CONFIG_CHANGES[@]}"
do
    json_data=$(echo "$json_data" | jq "$change")
done

# Write the modified JSON back to the file
echo "$json_data" > $CONFIGS_DIR/config.json
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

# Check if keys exist to start as relay or block producer
if [[ -n "$KES" ]]; then
    cardano-node run \
        --config $CONFIG \
        --topology $TOPOLOGY \
        --socket-path $SOCKET \
        --database-path $DB_DIR \
        --host-addr $CNODE_HOST \
        --port $CNODE_PORT \
        --shelley-kes-key $KES \
        --shelley-vrf-key $VRF \
        --shelley-operational-certificate $CERT
else
    cardano-node run \
        --config $CONFIG \
        --topology $TOPOLOGY \
        --socket-path $SOCKET \
        --database-path $DB_DIR \
        --host-addr $CNODE_HOST \
        --port $CNODE_PORT
fi

