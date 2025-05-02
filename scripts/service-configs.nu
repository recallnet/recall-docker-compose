
export def write-ipc-cli [] {
  let net = $env.node_config.network
  let patch = if ($env.node_config.parent_endpoint.token? | is-empty) {{}} else {
    auth_token: $env.node_config.parent_endpoint.token
  }

  {
    keystore_path: "/fendermint/.ipc"
    subnets: [
      {
        id: $"/r($net.parent_chain.chain_id)"
        config: ({
          network_type: "fevm"
          provider_http: $env.node_config.parent_endpoint.url
          gateway_addr: $net.parent_chain.addresses.gateway
          registry_addr: $net.parent_chain.addresses.registry
        } | merge $patch)
      }
      {
        id: $net.subnet.subnet_id
        config: {
          network_type: "fevm"
          provider_http: $"http://($env.node_config.project_name)-ethapi-1:8545"

          # These are static and deployed at subnet genesis
          gateway_addr: "0x77aa40b105843728088c0132e43fc44348881da8"
          registry_addr: "0x74539671a1d2f1c8f200826baba665179f53a1b7"
        }
      }
    ]
  } | save -f "/workdir/ipc/config.toml"
}

export def write-cometbft [] {
  let cfg = (open "/repo/config/services/cometbft.config.toml")

  let c = $env.node_config

  def statesync [] {
    # CometBFT requires at least 2 RPC servers. So if there is just one, we write it twice.
    def rpc-servers [] {
      let srv = if ($c.network.endpoints.cometbft_rpc_servers | length) > 1 {
        $c.network.endpoints.cometbft_rpc_servers
      } else {
        let x = ($c.network.endpoints.cometbft_rpc_servers | first)
        [$x $x]
      }
      $srv | str join ","
    }

    let disabled = { enable: false }

    if $c.services.cometbft_statesync_enable {
      let srv = ($c.network.endpoints.cometbft_rpc_servers | first)
      let last_block = (http get $"($srv)/abci_info" | get result.response.last_block_height | into int)
      if $last_block >= $c.services.fendermint_snapshot_block_interval {
        let trust_height = ($last_block - $c.services.fendermint_snapshot_block_interval)
        {
          enable: true
          rpc_servers: (rpc-servers)
          trust_height: $trust_height
          trust_hash: (http get $"($srv)/block?height=($trust_height)" | get result.block_id.hash)
        }
      } else {
        # There are no snapshots yet.
        $disabled
      }
    } else {
      $disabled
    }
  }

  $cfg | merge deep {
    proxy_app: $"tcp://($c.project_name)-fendermint-1:26658"
    moniker: $c.node_name
    p2p: {
      external_address: (if ($c.networking.advertised_external_ip? | is-empty) {""} else {$"($c.networking.advertised_external_ip):($c.networking.external_ports.cometbft)"})
      persistent_peers: ($c.network.endpoints.cometbft_persistent_peers | str join ",")
    }
    statesync: (statesync)
  } | save -f /workdir/cometbft/config/config.toml
}


# # Fendermint
# mkdir -p /workdir/fendermint/config
# envsubst < /repo/config/services/fendermint.config.toml > /workdir/fendermint/config/default.toml

# # Prometheus
# prom_targets_dir=/workdir/prometheus/etc/targets
# rm -rf $prom_targets_dir
# rm -rf /workdir/prometheus/etc/rules
# mkdir -p $prom_targets_dir
# mkdir -p /workdir/prometheus/etc/rules
# mkdir -p /workdir/prometheus/data
# chown nobody /workdir/prometheus/data
# envsubst < /repo/config/services/prometheus.yml > /workdir/prometheus/etc/config.yml

# # Relayer
# if [ $enable_relayer == "true" ]; then
#   mkdir -p /workdir/relayer/ipc
#   export relayer_address=$(jq -r '.[].address' < /workdir/relayer/ipc/evm_keystore.json)
#   export keystore_path=/relayer/ipc
#   envsubst < /repo/config/services/run-relayer.sh > /workdir/relayer/run.sh
#   envsubst < /repo/config/services/ipc.config.toml > /workdir/relayer/ipc/config.toml
#   echo '[{"targets":["'${project_name}'-relayer-1:9184"]}]' > $prom_targets_dir/relayer.json
# fi

# if [ $enable_registrar == "true" ]; then
#   export recall_exporter_subnet_faucet_contract_address=$subnet_faucet_contract_address
#   echo '[{"targets":["'${project_name}'-registrar-1:9090"]}]' > $prom_targets_dir/registrar.json
# fi

# if [ $enable_recall_s3 == "true" ]; then
#   echo '[{"targets":["'${project_name}'-recall-s3-1:9090"]}]' > $prom_targets_dir/recall-s3.json
# fi

# # === Generated
# # It's using some environment variables set above!!!
# mkdir -p /workdir/generated
# function write_env {
#   local cfg=$1
#   local source_file=/repo/config/services/$1
#   (
#     source $source_file
#     cat $source_file | awk -F '=' '/=/ {print $1 "=\"" ENVIRON[$1] "\""}' > /workdir/generated/$cfg
#   )
# }
# set -a
# subnet_prefix=$(echo $docker_network_subnet | sed -e 's|\.[0-9]*/.*||')
# write_env service-ips.env
# source /workdir/generated/service-ips.env

# write_env fendermint.env
# write_env ethapi.env
# write_env objects.env
# write_env recall-exporter.env
# if [ $enable_recall_s3 == "true" ]; then write_env recall-s3.env; fi
# if [ $enable_registrar == "true" ]; then write_env registrar.env; fi
