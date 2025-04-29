# Recall docker-compose

This repository contains scripts to deploy a recall node with docker-compose.

## Hardware Requirements

To run a Recall validator Node, the following hardware is strongly recommended:

| Hardware          | TestNet  | MainNet   |
|-------------------|----------|-----------|
| CPU cores         | 8        | 8         |
| Memory            | 32 (GB)  | 32 (GB)   |
| Disk space <sup>(1)</sup>    | 50 (TB)  | 512 (TB)  |
| Network bandwidth | 1 GB/s   | 1 GB/s    |
| Public IP Address | 1        | 1         |

<sup>(1)</sup> Plain old hard disks drive levels of performance is acceptable.

Please note that we are working on features that may help alleviate the storage requirement, but those are not available at this time.

## Starting a node
1. Copy `config/node-template.env` to `config/node.env`
2. Edit `config/node.env`. `node.env` overwrites values from `./config/node-default.env`
   * Note: you can create new keys with `./run.sh create-key`.
   * Note: the node address must be known on the network. Visit https://faucet.recall.network/ to receive funds.
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

### Firewall
Make sure the ports `external_*_ports` defined in `config/node-default.env` are open on the host machine:
* `external_cometbft_port` - CometBFT p2p port (TCP)
* `external_fendermint_port` - Fendermint p2p port (TCP)
* `external_fendermint_iroh_port` - Fendermint Iroh p2p port (UDP)
* `external_objects_iroh_port` - Objects Iroh p2p port (UDP)

## Joining network as a validator
1. Ask for whitelisting in `TODO` telegram channel.
2. The recall team will whitelist your address and let you know the required amount in RECALL tokens you can use as collateral to join the subnet as a validator.
3. Join the subnet `./run.sh join-subnet <collateral in whole RECALL units>`

## Recall Node Components
* [CometBFT](https://cometbft.com/), a standard blockchain application platform for consensus
* [Fendermint](https://github.com/recallnet/ipc/blob/main/docs/fendermint), a specialized ABCI++ interface to FEVM/FVM
* Ethereum RPC, a standard endpoint for ETH API access (provided by fendermint).
* Blob API, the Recall endpoint for data blob storage and retrieval (provided by fendermint)
* [recall-exporter](https://github.com/recallnet/recall-exporter), scrapes subnet specific metrics

## Monitoring
There is a prometheus instance that scrapes metrics from all recall node compoenents.
You can deploy an additional prometheus server and scrape metrics from the node prometheus.
For details see [prometheus docs on federation](https://prometheus.io/docs/prometheus/latest/federation/).
If your prometheus server is running in a docker container, you can set `prometheus_external_network` to make prometheus container to join an external network.

## Testnet Node Reset
To reset a testnet node, you have to run the following steps:
1. Stop the node: `./run.sh stop`
2. Remove the node data: `rm -r ./workdir` and eventually the `datadir` if it is located outside of `workdir`.
3. Pull the latest changes: `git pull`
4. Get some funds from the faucet: `https://faucet.recall.network/`
5. Initialize the node: `./run.sh init`
6. Start the node: `./run.sh up -d`

### Join Subnet
1. Reach out to the Recall team to get your node address approved.
2. Join the subnet: `./run.sh join-subnet 3` (3 is just an example, it is the collateral in full RECALL units).
