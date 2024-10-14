# cardano-docker

Docker compose for cardano relay and block producer node. 

## Configuration
Since cardano node does not support override of configurations with command line arguments or environment variables, this repo will always download latest config from official URLS below. In order to override any value in the config, use .env file and add the changes to `CONFIG_UPDATES` variable. The config will be updated when the node is starting up.

```bash
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/config.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/db-sync-config.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/submit-api-config.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/topology.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/byron-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/shelley-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/alonzo-genesis.json
curl -O -J https://book.world.dev.cardano.org/environments/${NETWORK}/conway-genesis.json
```

Supports the following networks:
1. Testnet / Preview
    ```bash
    NetworkMagic: 2

    # Alternative check tip for any network
    ./ethd tip
    ```
2. Testnet / Preprod
    ```bash
    NetworkMagic: 1

    # NB can use alternative
    ```
3. Mainnet / Production
    ```bash
    NetworkMagic: 764824073

    # NB can use alternative
    ```

Patterned after eth-docker and meant to be used with https://github.com/CryptoManufaktur-io/base-docker-environment for traefik and Prometheus.

You can copy `ext-network.yml.sample` to `ext-network.yml` and allow the node to run on same network as where traefik and prometheus run. This will allow proxy and metrics to work without exposing their ports and just using docker service discovery with service names.

`./ethd install` can install docker-ce for you

`cp default.env .env`, adjust variables, and `./ethd up`

There's an `rpc-shared.yml` if you want the RPC exposed locally, instead of via traefik, also similar there is `metrics-shared.yml` to expose metrics.

To update cardano, use `./ethd update` followed by `./ethd up`

This is cardano-docker v1.0

