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
1. Copy `config/node-template.toml` to `config/node.toml`
2. Edit `config/node.toml`. `node.toml` overwrites values from `./config/node-default.toml`
   * Note: you can generate new keys with `./generate-key`.
   * Note: the node address must be known on the network. Visit https://faucet.recall.network/ to receive funds.
3. Run `./init-workdir <path>` - This will create in `workdir` required configuration for node services based on your configuration in `node.toml`. Default is `./workdir`.
4. Run `cd workdir; docker compose up -d` to run detached.
   * The node will download the latest snapshot and start syncronizing remaining blocks.
   * Inspect output of `./workdir/node-tools status`. A node is in sync with the network when `catching_up: false`.

### Customizing node configuration
`./config/node-template.toml` contains a minimal configuration to run a node.
More advanced configuration options can be found `./config/node-default.toml`
Consider adjusting the following options:
* `datadir` that contains the uploaded user blobs, default `./data`. The path must be either absolute or relative to `workdir`.
* `networking.docker_network_subnet` - you might want to change the default if the subnet overlaps with your internal networks. The network should have at least 256 addresses (`/24` mask). Every service gets a fixed IP address within that subnet.

### Firewall
Make sure the ports `networking.external_ports` defined in `config/node-default.toml` are open on the host machine:
* `cometbft` - CometBFT p2p port (TCP)
* `fendermint` - Fendermint p2p port (TCP)
* `fendermint_iroh` - Fendermint Iroh p2p port (UDP)
* `objects_iroh` - Objects Iroh p2p port (UDP)

## Joining network as a validator
1. Reach out to the Recall team to get your node address approved.
2. Join the subnet: `cd workdir; ./node-tools join-subnet <collateral in whole RECALL units>`.

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
1. Stop the node: `cd workdir; docker compose down`
2. Remove the node data: `rm -r ./workdir` and eventually the `datadir` if it is located outside of `workdir`.
3. Pull the latest changes: `git pull`
4. Get some funds from the faucet: `https://faucet.recall.network/`
5. Initialize the node: `./init-workdir`
6. Start the node: `cd workdir; docker compose up -d`

### Join Subnet
1. Reach out to the Recall team to get your node address approved.
2. Join the subnet: `cd workdir; ./node-tools join-subnet <collateral in whole RECALL units>`.
