
set -eu

# CometBFT
if [ "$cometbft_statesync_enable" == "true" ]; then
  last_block=$(curl -s https://$seed_node_api_host/abci_info | jq -r '.result.response.last_block_height')
  export trusted_block_height=$(($last_block - $fendermint_snapshot_block_interval))
  export trusted_block_hash=$(curl -s https://$seed_node_api_host/block?height=$trusted_block_height | jq -r '.result.block_id.hash')
else
  export trusted_block_height=0
fi

envsubst < /repo/config/services/cometbft.config.toml > /workdir/cometbft/config/config.toml


# Fendermint
mkdir -p /workdir/fendermint/config
envsubst < /repo/config/services/fendermint.config.toml > /workdir/fendermint/config/default.toml

# Hoku exporter
validator_address=$(cat /workdir/generated/ipc/evm_keystore.json | jq -r '.[].address')
echo "validator_address=$validator_address" > /workdir/generated/hoku-exporter.env

# Caddy
mkdir -p /workdir/caddy
caddyfile=/workdir/caddy/Caddyfile
function write_proxy {
  local dns_name=$1
  local target=$2
  cat >> $caddyfile <<EOF
$dns_name {
  reverse_proxy $target
  tls $acme_email
}
EOF
}
cat > $caddyfile <<EOF
{
  servers {
    metrics
  }
}
http://caddy:9090 {
  bind 0.0.0.0
  metrics
}
EOF
write_proxy $dns_api cometbft:26657
write_proxy $dns_evm ethapi:8545
write_proxy $dns_objects objects:8001
write_proxy $dns_faucet faucet:8080
write_proxy $dns_basin_s3 basin-s3:8014

# Prometheus
prom_targets_dir=/workdir/prometheus/targets
rm -rf $prom_targets_dir
rm -rf /workdir/prometheus/alertmanager
mkdir -p $prom_targets_dir
mkdir -p /workdir/prometheus/alertmanager
envsubst < /repo/config/services/prometheus.yml > /workdir/prometheus/config.yml

# Relayer
if [ $enable_relayer == "true" ]; then
  mkdir -p /workdir/relayer/ipc
  export relayer_address=$(jq -r '.[].address' < /workdir/relayer/ipc/evm_keystore.json)
  envsubst < /repo/config/services/run-relayer.sh > /workdir/relayer/run.sh
  envsubst < /repo/config/services/relayer.ipc.config.toml > /workdir/relayer/ipc/config.toml
  echo '[{"targets":["relayer:9184"]}]' > $prom_targets_dir/relayer.json
fi

# if [ $enable_faucet == "true" ]; then
#   echo '[{"targets":["faucet:9090"]}]' > $prom_targets_dir/faucet.json
# fi

if [ $enable_basin_s3 == "true" ]; then
  echo '[{"targets":["basin-s3:9090"]}]' > $prom_targets_dir/basin-s3.json
fi

