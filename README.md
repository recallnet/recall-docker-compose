# Recall docker-compose

This repository contains scripts to deploy a recall node with docker-compose.

## Hardware Requirements

To run a Recall validator Node, the following hardware is strongly recommended:

| Hardware          | TestNet  | MainNet   |
|-------------------|----------|-----------|
| CPU cores         | 8        | 8         |
| Memory            | 32 (GB)  | 32 (GB)   |
| Disk space <sup>(1)</sup>    | 32 (TB)  | 480 (TB)  |
| Network bandwidth | 1 GB/s   | 1 GB/s    |
| Public IP Address | 1        | 1         |

<sup>(1)</sup> Plain old hard disks drive levels of performance is acceptable.

Please note that we are working on features that may help alleviate the storage requirement, but those are not available at this time.

## Starting a node
1. Copy `config/node-template.env` to `config/node.env`
2. Edit `config/node.env`. `node.env` overwrites values from `./config/node-default.env`
   * Note: you can create new keys with `./run.sh create-key`.
   * Note: the node address must be known on the network. Visit https://faucet.node-0.testnet.recall.network/ to receive funds.
3. Run `./run.sh init` - This will create required configuration for node services based on your configuration in `node.env`.
4. Run `./run.sh up` or `./run.sh up -d` to run detached.
   * The node will download the latest snapshot and start syncronizing remaining blocks.
   * When the node is in sync with the network, `cometbft` service logs `finalizing commit of block` for every committed block.

### Customizing node configuration
`./config/node-template.env` contains a minimal configuration to run a node.
More advanced configuration options can be found `./config/node-default.env`
Consider adjusting the following options:
* `datadir` that contains the uploaded user blobs, default `./workdir/data`
* `prometheus_external_network` - external docker network that prometheus will join. This can be used to scrape metrics from prometheus in another prometheus instance in an external network.

## Joining network as a validator
1. Ask for whitelisting in `TODO` telegram channel.
2. The recall team will whitelist your address and let you know the required amount in RECALL tokens you can use as collateral to join the subnet as a validator.
3. Join the subnet `./run.sh join-subnet <collateral in whole RECALL units>`

## Recall Node Components
* [CometBFT](https://cometbft.com/), a standard blockchain application platform for consensus
* [Fendermint](https://github.com/recallnet/ipc/blob/main/docs/fendermint), a specialized ABCI++ interface to FEVM/FVM
* Ethereum RPC, a standard endpoint for ETH API access (provided by fendermint).
* Blob API, the Recall endpoint for data blob storage and retrieval (provided by fendermint)
* [Iroh](https://github.com/n0-computer/iroh), provides data synchronization between nodes
* [recall-exporter](https://github.com/recallnet/recall-exporter), scrapes subnet specific metrics

## Monitoring
There is a prometheus instance that scrapes metrics from all recall node compoenents.
You can deploy an additional prometheus server and scrape metrics from the node prometheus.
For details see [prometheus docs on federation](https://prometheus.io/docs/prometheus/latest/federation/).
If your prometheus server is running in a docker container, you can set `prometheus_external_network` to make prometheus container to join an external network.
