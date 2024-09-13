#!/bin/bash
WORK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE}")")
cd $WORK_DIR

curl -O -J https://book.world.dev.cardano.org/environments/preprod/config.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/db-sync-config.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/submit-api-config.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/topology.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/byron-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/shelley-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/alonzo-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/preprod/conway-genesis.json