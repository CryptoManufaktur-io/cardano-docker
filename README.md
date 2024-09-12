# cardano-docker

Docker compose for cardano relay and block producer node. 

## Configuration
Since cardano node does not support override of configurations with command line arguments or environment variables, this repo does not contain any configuration by default. Instead there are sample configs on `sample_config` folder for all supported networks. You need to copy the specific network configs to the folder `config` on root directory and edit accordingly before running the node. This makes the repo very dynamic and can support cardano relays and block producer at same time.

NB: `sample_config` has default config from cardano `https://book.world.dev.cardano.org`. You can also download the config files from there if the ones on `sample_config` are outdated.

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

Example to copy mainnet config: This will create a folder `config/mainnet` with configurations for mainnet network.
```bash
cp sample_config/mainnet/* config/
```

Supports the following networks:
1. Testnet / Preview
    ```bash
    NetworkMagic: 2

    # Check tip
    docker compose exec cardano-node cardano-cli query tip --testnet-magic 2

    # Alternative check tip for any network
    ./ethd tip
    ```
2. Testnet / Preprod
    ```bash
    NetworkMagic: 1

    # Check tip
    docker compose exec cardano-node cardano-cli query tip --testnet-magic 1

    # NB can use alternative
    ```
3. Mainnet / Production
    ```bash
    NetworkMagic: 764824073

    # Check tip
    docker compose exec cardano-node cardano-cli query tip --mainnet

    # NB can use alternative
    ```

Patterned after eth-docker and meant to be used with https://github.com/CryptoManufaktur-io/base-docker-environment for traefik and Prometheus.

You can copy `ext-network.yml.sample` to `ext-network.yml` and allow the node to run on same network as where traefik and prometheus run. This will allow proxy and metrics to work without exposing their ports and just using docker service discovery with service names.

`./ethd install` can install docker-ce for you

`cp default.env .env`, adjust variables, and `./ethd up`

There's an `rpc-shared.yml` if you want the RPC exposed locally, instead of via traefik

To update cardano, use `./ethd update` followed by `./ethd up`

This is cardano-docker v1.0

