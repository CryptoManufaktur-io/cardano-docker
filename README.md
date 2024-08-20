# cardano-docker

Docker compose for cardano full node. Supports the following networks
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

`ext-network.yml` assumes a `traefik` network exists, where traefik and prometheus run

`./ethd install` can install docker-ce for you

`cp default.env .env`, adjust variables, and `./ethd up`

There's an `rpc-shared.yml` if you want the RPC exposed locally, instead of via traefik

To update cardano, use `./ethd update` followed by `./ethd up`

This is cardano-docker v1.0

