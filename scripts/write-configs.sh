
set -eu

source /repo/scripts/read-config.sh

# ipc-cli
export validator_address=$(jq -r '.[].address' < /workdir/ipc/evm_keystore.json)
export keystore_path="/fendermint/.ipc"
envsubst < /repo/config/services/ipc.config.toml > /workdir/ipc/config.toml

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
prom_targets_dir=/workdir/prometheus/etc/targets
rm -rf $prom_targets_dir
rm -rf /workdir/prometheus/etc/alertmanager
rm -rf /workdir/prometheus/etc/rules
mkdir -p $prom_targets_dir
mkdir -p /workdir/prometheus/etc/alertmanager
mkdir -p /workdir/prometheus/etc/rules
cp /repo/config/services/alerts.yml /workdir/prometheus/etc/rules/
envsubst < /repo/config/services/prometheus.yml > /workdir/prometheus/etc/config.yml
[ ! -z $alertmanager_address ] && echo '[{"targets":["'$alertmanager_address'"]}]' > /workdir/prometheus/etc/alertmanager/instance0.json

# Relayer
if [ $enable_relayer == "true" ]; then
  mkdir -p /workdir/relayer/ipc
  export relayer_address=$(jq -r '.[].address' < /workdir/relayer/ipc/evm_keystore.json)
  export keystore_path=/relayer/ipc
  envsubst < /repo/config/services/run-relayer.sh > /workdir/relayer/run.sh
  envsubst < /repo/config/services/ipc.config.toml > /workdir/relayer/ipc/config.toml
  echo '[{"targets":["relayer:9184"]}]' > $prom_targets_dir/relayer.json
fi

# if [ $enable_faucet == "true" ]; then
#   echo '[{"targets":["faucet:9090"]}]' > $prom_targets_dir/faucet.json
# fi

if [ $enable_basin_s3 == "true" ]; then
  echo '[{"targets":["basin-s3:9090"]}]' > $prom_targets_dir/basin-s3.json
fi

# === Generated
mkdir -p /workdir/generated
set -a
for cfg in /repo/config/services/*.env; do
  source $cfg
  cat $cfg | awk -F '=' '/=/ {print $1 "=\"" ENVIRON[$1] "\""}' > /workdir/generated/$(basename $cfg)
done

