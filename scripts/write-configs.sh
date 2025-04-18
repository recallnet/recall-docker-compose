
set -eu

source /repo/scripts/read-config.sh

# === parent endpoint token
set +u
if [ ! -z "$parent_endpoint_token" ]; then
  export recall_exporter_parent_endpoint_token="$parent_endpoint_token"
  export ipc_config_parent_endpoint_token="auth_token = '$parent_endpoint_token'"
  export fendermint_parent_endpoint_token="parent_http_auth_token = '$parent_endpoint_token'"
fi
set -u

# ipc-cli
export validator_address=$(jq -r '.[].address' < /workdir/ipc/evm_keystore.json)
export keystore_path="/fendermint/.ipc"
envsubst < /repo/config/services/ipc.config.toml > /workdir/ipc/config.toml

# CometBFT
if [ "$cometbft_statesync_enable" == "true" ]; then
  first_server=$(echo $cometbft_rpc_servers | sed -e s/',.*'//)
  last_block=$(curl -s $first_server/abci_info | jq -r '.result.response.last_block_height')
  if [ $last_block -gt $fendermint_snapshot_block_interval ]; then
    export trusted_block_height=$(($last_block - $fendermint_snapshot_block_interval))
    export trusted_block_hash=$(curl -s https://$seed_node_api_host/block?height=$trusted_block_height | jq -r '.result.block_id.hash')
  else
    export cometbft_statesync_enable="false"
    export trusted_block_height=0
  fi
else
  export trusted_block_height=0
fi
if [ ! -z "$advertised_external_ip" ]; then
  export cometbft_external_address="$advertised_external_ip:$external_cometbft_port"
fi

envsubst < /repo/config/services/cometbft.config.toml > /workdir/cometbft/config/config.toml


# Fendermint
mkdir -p /workdir/fendermint/config
envsubst < /repo/config/services/fendermint.config.toml > /workdir/fendermint/config/default.toml

# Prometheus
prom_targets_dir=/workdir/prometheus/etc/targets
rm -rf $prom_targets_dir
rm -rf /workdir/prometheus/etc/rules
mkdir -p $prom_targets_dir
mkdir -p /workdir/prometheus/etc/rules
mkdir -p /workdir/prometheus/data
chown nobody /workdir/prometheus/data
envsubst < /repo/config/services/prometheus.yml > /workdir/prometheus/etc/config.yml

# Relayer
if [ $enable_relayer == "true" ]; then
  mkdir -p /workdir/relayer/ipc
  export relayer_address=$(jq -r '.[].address' < /workdir/relayer/ipc/evm_keystore.json)
  export keystore_path=/relayer/ipc
  envsubst < /repo/config/services/run-relayer.sh > /workdir/relayer/run.sh
  envsubst < /repo/config/services/ipc.config.toml > /workdir/relayer/ipc/config.toml
  echo '[{"targets":["'${project_name}'-relayer-1:9184"]}]' > $prom_targets_dir/relayer.json
fi

if [ $enable_registrar == "true" ]; then
  export recall_exporter_subnet_faucet_contract_address=$subnet_faucet_contract_address
  echo '[{"targets":["'${project_name}'-registrar-1:9090"]}]' > $prom_targets_dir/registrar.json
fi

if [ $enable_recall_s3 == "true" ]; then
  echo '[{"targets":["'${project_name}'-recall-s3-1:9090"]}]' > $prom_targets_dir/recall-s3.json
fi

# === Generated
# It's using some environment variables set above!!!
mkdir -p /workdir/generated
function write_env {
  local cfg=$1
  local source_file=/repo/config/services/$1
  (
    source $source_file
    cat $source_file | awk -F '=' '/=/ {print $1 "=\"" ENVIRON[$1] "\""}' > /workdir/generated/$cfg
  )
}
set -a
write_env fendermint.env
write_env ethapi.env
write_env objects.env
write_env recall-exporter.env
if [ $enable_recall_s3 == "true" ]; then write_env recall-s3.env; fi
if [ $enable_registrar == "true" ]; then write_env registrar.env; fi
