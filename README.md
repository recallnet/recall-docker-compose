# Hoku docker-compose

This repository contains scripts to deploy a hoku node with docker-compose.

## Starting a node
1. Copy `config/node-template.env` to `config/node.env`
2. Edit `config/node.env`. `node.env` overwrites values from `./config/node-default.env`
   * Note: you can create new keys with `./run.sh create-key`.
   * Note: the node address must be known on the network. Visit https://faucet.hoku.sh/ to receive funds.
3. Run `./run.sh init` - This will create required configuration for node services based on your configuration in `node.env`.
4. Run `./run.sh up` or `./run.sh up -d` to run detached.
   * The node will download the latest snapshot and start syncronizing remaining blocks.
   * When the node is in sync with the network, `cometbft` service logs `finalizing commit of block` for every committed block.

### Customizing node configuration
`./config/node-template.env` contains a minimal configuration to run a node.
More advanced configuration options can be found `./config/node-default.env`
Consider adjusting the following options:
* `datadir` that contains the uploaded user blobs, default `./workdir/data`
* `alertmanager_address` - prometheus server will push alerts to the specified address.

## Joining network as a validator
1. Ask for whitelisting in `TODO` telegram channel.
2. The hoku team will whitelist your address and let you know the required amount in tHOKU tokens you can use as collateral to join the subnet as a validator.
3. Join the subnet `./run.sh join-subnet <collateral in whole tHOKU units>`
