#!/bin/bash
set -eu

# Check if DB_DIR exists and is empty, and if SNAPSHOT is set and not empty
if [[ -d "${DB_DIR}" && -z "$(ls -A ${DB_DIR})" ]] && [[ -n "${SNAPSHOT}" ]]; then
    mkdir -p /runtime/temp
    FILENAME="/runtime/temp/snapshot.tar.lz4"
    
    echo "Downloading snapshot from ${SNAPSHOT}..."
    wget -O "${FILENAME}" "${SNAPSHOT}" --progress=dot:giga

    # Check if the file was downloaded successfully
    if [[ -f "${FILENAME}" ]]; then
        echo "Extracting ${FILENAME} to ${DB_DIR}..."
        lz4 -dvc --no-sparse "${FILENAME}" | tar xv --strip-components=1 -C "${DB_DIR}"

        # Check if the extraction was successful
        if [[ $? -eq 0 ]]; then
            echo "Extraction for snapshot successful!"
            rm -rf /runtime/temp
        else
            echo "Error: Extraction for snapshot failed."
            exit 1
        fi
    else
        echo "Error: Failed to download snapshot file."
        exit 1
    fi
else
    echo "No snapshot provided or already synced"
fi


# Check if KES is not empty
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

