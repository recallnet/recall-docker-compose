#!/usr/bin/env bash

set -eu

source /repo/scripts/read-config.sh

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

function download_from_parent_chain {
  fendermint genesis --genesis-file $raw \
    ipc from-parent \
    --subnet-id $subnet_id \
    --parent-endpoint $parent_endpoint \
    ${parent_endpoint_token:+--parent-auth-token $parent_endpoint_token} \
    --parent-gateway $parent_gateway_address \
    --parent-registry $parent_registry_address

  fendermint genesis --genesis-file $raw set-eam-permissions --mode unrestricted
  set +u
  if [ ! -z "$chain_id" ]; then
    fendermint genesis --genesis-file $raw set-chain-id --chain-id $chain_id
  fi
  set -u

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
}

function download_from_peer {
  local remote=$(echo $cometbft_rpc_servers | sed -e s/',.*'//)
  local total=100
  local ix=0
  local genesis_tmp=$genesis_dir/genesis.tmp
  local genesis_chunk=$genesis_dir/genesis.chunk

  rm -f $genesis_tmp $genesis_chunk
  while [ $ix -lt $total ]; do
    curl -so $genesis_chunk $remote/genesis_chunked?chunk=$ix
    if [ $total -eq 100 ]; then
      total=$(jq -r '.result.total' < $genesis_chunk)
    fi
    jq -r '.result.data' < $genesis_chunk | base64 -d >> $genesis_tmp
    ix=$((ix+1))
  done
  mv $genesis_tmp $dest
  rm -f $genesis_chunk
}

has_fendermint_command=$(command -v fendermint &> /dev/null && echo "true" || echo "false")
if [ "$cometbft_statesync_enable" == "true" ]; then
  download_from_peer
elif [ "$has_fendermint_command" == "true" ]; then
  download_from_parent_chain
else
  exit 0;
fi

cp $dest /cometbft/config/
