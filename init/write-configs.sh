
set -eux

# CometBFT
if [ "$cometbft_statesync_enable" == "true" ]; then
  last_block=$(curl -s https://$seed_node_api_host/abci_info | jq -r '.result.response.last_block_height')
  export trusted_block_height=$(($last_block - $fendermint_snapshot_block_interval))
  export trusted_block_hash=$(curl -s https://$seed_node_api_host/block?height=$trusted_block_height | jq -r '.result.block_id.hash')
else
  export trusted_block_height=0
fi

envsubst < /repo/config/services/cometbft.config.toml > $cometbft_dir/config/config.toml 


# Fendermint
mkdir -p /workdir/fendermint/config
envsubst < /repo/config/services/fendermint.config.toml > $fendermint_dir/config/default.toml 

# Hoku exporter
validator_address=$(cat /workdir/generated/ipc/evm_keystore.json | jq -r '.[].address') 
echo "validator_address=$validator_address" > /workdir/generated/hoku-exporter.env

# Relayer
if [ $relayer_replicas == 1 ]; then
  mkdir -p /workdir/relayer/ipc
  export relayer_address=$(jq -r '.[].address' < $relayer_dir/ipc/evm_keystore.json)
  envsubst < /repo/config/services/run-relayer.sh > $relayer_dir/run.sh
  envsubst < /repo/config/services/relayer.ipc.config.toml > $relayer_dir/ipc/config.toml
fi
