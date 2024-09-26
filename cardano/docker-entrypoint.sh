#!/bin/bash
set -eu

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

