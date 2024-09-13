#!/bin/bash
WORK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE}")")
cd $WORK_DIR

curl -O -J https://book.world.dev.cardano.org/environments/mainnet/config.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/db-sync-config.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/submit-api-config.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/topology.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/byron-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/shelley-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/alonzo-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/mainnet/conway-genesis.json