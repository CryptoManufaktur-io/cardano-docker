# Overview

Cardano Ogmias RPC node docker-compose, to be used with eth-docker's traefik.

To get started: `cp default.env .env`, adjust `COMPOSE_FILE`, the desired `CARDANO_TAG` and your traefik variables if you use traefik, then `docker-compose up -d`.

To update cardano, edit `CARDANO_TAG` in `.env` to the version you want and `docker-compose pull`, then `docker-compose down && docker-compose up -d` 

`cardano-haproxy.cfg` is a sample haproxy configuration file. `check-cardanosync.sh` verifies sync status for haproxy. `haproxy-docker-sample.yml` is an example for a docker-compose file running haproxy, inside a docker swarm mode.

