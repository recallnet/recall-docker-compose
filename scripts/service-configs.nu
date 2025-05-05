
def write-docker-service [name: string, service_config: record] {
  let dc_file = "/workdir/docker-compose.yml"
  let content = if ($dc_file | path exists) {
    open $dc_file
  } else {{
    name: $env.node_config.project_name
  }}

  let srv = ($service_config | merge {
    restart: "always"
    networks: {
      default: {
        ipv4_address: (service-ip $name)
      }
    }
  })

  $content | merge deep {
    services: ({} | insert $name $srv )
  } | save -f $dc_file
}

def service-ip [service: string] {
  let prefix = ($env.node_config.networking.docker_network_subnet | str replace -r "\\.\\d+/.*" "")
  match $service {
    "cometbft" => $"($prefix).10"
    "fendermint" => $"($prefix).11"
    "ethapi" => $"($prefix).12"
    "objects" => $"($prefix).13"
    "recall-exporter" => $"($prefix).14"
    "prometheus" => $"($prefix).15"
    "relayer" => $"($prefix).16"

    "recall-s3" => $"($prefix).20"
    "registrar" => $"($prefix).21"
  }
}

def ipc-config [keystore_path] {
  let net = $env.node_config.network
  let patch = if ($env.node_config.parent_endpoint.token? | is-empty) {{}} else {
    auth_token: $env.node_config.parent_endpoint.token
  }

  {
    keystore_path: $keystore_path
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
  }
}

def write-ipc-key [dir, private_key] {
  let addr = (cast wallet address $private_key)

  [{
    address: $addr
    private_key: ($private_key | str replace "0x" "")
  }] | save -f ($dir | path join "evm_keystore.json")
}

export def write-ipc-cli [] {
  mkdir /workdir/ipc
  ipc-config "/fendermint/.ipc" | save -f "/workdir/ipc/config.toml"
  write-ipc-key /workdir/ipc $env.node_config.node_private_key
}

export def write-cometbft [] {
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

  open "/repo/config/services/cometbft.config.toml" | merge deep {
    proxy_app: $"tcp://($c.project_name)-fendermint-1:26658"
    moniker: $c.node_name
    p2p: {
      external_address: (if ($c.networking.advertised_external_ip? | is-empty) {""} else {$"($c.networking.advertised_external_ip):($c.networking.external_ports.cometbft)"})
      persistent_peers: ($c.network.endpoints.cometbft_persistent_peers | str join ",")
    }
    statesync: (statesync)
  } | save -f /workdir/cometbft/config/config.toml
}

export def write-fendermint [] {
  mkdir "/workdir/fendermint/config"
  let c = $env.node_config

  open "/repo/config/services/fendermint.config.toml" | merge deep {
    tendermint_rpc_url: $"http://($c.project_name)-cometbft-1:26657"
    snapshots: {
      block_interval: $c.services.fendermint_snapshot_block_interval
    }
    ipc: {
      subnet_id: $c.network.subnet.subnet_id
      topdown: ({
        parent_http_endpoint: $c.parent_endpoint.url
        parent_gateway: $c.network.parent_chain.addresses.gateway
        parent_registry: $c.network.parent_chain.addresses.registry
      } | merge (if ($c.parent_endpoint.token? | is-empty) {{}} else {{
        parent_http_auth_token: $c.parent_endpoint.token
      }}))
    }
  } | save -f "/workdir/fendermint/config/default.toml"
}

const prom_targets_dir = "/workdir/prometheus/etc/targets"
export def write-prometheus [] {
  rm -rf $prom_targets_dir
  rm -rf "/workdir/prometheus/etc/rules"
  mkdir $prom_targets_dir
  mkdir "/workdir/prometheus/etc/rules"
  mkdir "/workdir/prometheus/data"
  chown nobody /workdir/prometheus/data

  let c = $env.node_config
  {
    global: {
      scrape_interval: "15s"
    }
    scrape_configs: [
      {
        job_name: "node-components"
        static_configs: [
          {
            targets: [
              $"($c.project_name)-recall-exporter-1:9010"
              $"($c.project_name)-cometbft-1:26660"
              $"($c.project_name)-fendermint-1:9184"
              $"($c.project_name)-objects-1:9186"
              $"($c.project_name)-ethapi-1:9185"
            ]
          }
        ]
        file_sd_configs: [
          {
            files: [
              "/etc/prometheus/targets/*.json"
              "/etc/prometheus/targets/*.yml"
            ]
          }
        ]
        relabel_configs: [
          {
            action: "replace"
            target_label: "subnet_id"
            replacement: $c.network.subnet.subnet_id
          }
          {
            action: "replace"
            target_label: "node_name"
            replacement: $c.node_name
          }
          {
            action: "replace",
            target_label: "network_name"
            replacement: $c.network_name
          }
        ]
      }
    ]
    rule_files: [ "/etc/prometheus/rules/*.yml" ]
  } | save -f "/workdir/prometheus/etc/config.yml"
}

export def write-relayer [] {
  mkdir /workdir/relayer/ipc
  let c = $env.node_config
  let addr = (cast wallet address $c.relayer.private_key)

  # ipc-config
  ipc-config "/relayer/ipc" | save -f /workdir/relayer/ipc/config.toml
  write-ipc-key /workdir/relayer/ipc $c.relayer.private_key

  # container
  cp /repo/config/services/run-relayer.sh /workdir/relayer/run.sh
  write-docker-service "relayer" {
    image: $c.images.fendermint
    entrypoint: "sh /relayer/run.sh"
    volumes: [
      $"($c.directories.workdir)/relayer:/relayer"
    ]
    environment: {
      subnet_id: $c.network.subnet.subnet_id
      relayer_address: $addr
    }
    depends_on: [ "fendermint" ]
  }

  # metrics
  [{
    targets: [ $"($c.project_name)-relayer-1:9184"]
  }] | save -f $"($prom_targets_dir)/relayer.json"
}

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
