#!/usr/bin/env bash

set -eux

genesis_dir="/cometbft/genesis"
dest="$genesis_dir/genesis.json"

if [ -e $dest ]; then
  echo "$dest already exists"
  exit 0
fi

echo "Downloading genesis"

export FM_NETWORK=$address_network
raw=$genesis_dir/genesis.raw.json
sealed=$genesis_dir/genesis.sealed.json

mkdir -p $genesis_dir

fendermint genesis --genesis-file $raw \
  ipc from-parent \
  --subnet-id $subnet_id \
  --parent-endpoint $parent_endpoint \
  --parent-auth-token $parent_endpoint_token \
  --parent-gateway $parent_gateway_address \
  --parent-registry $parent_registry_address

fendermint genesis --genesis-file $raw set-eam-permissions --mode unrestricted

fendermint genesis --genesis-file $raw \
  ipc seal-genesis \
  --builtin-actors-path /fendermint/bundle.car \
  --custom-actors-path /fendermint/custom_actors_bundle.car \
  --artifacts-path /fendermint/contracts \
  --output-path $sealed

fendermint genesis --genesis-file $raw \
  into-tendermint \
  --app-state $sealed \
  --out $dest

cd /cometbft/config
ln -sf ../genesis/genesis.json
