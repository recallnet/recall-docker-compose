
const dc_file = "/workdir/docker-compose.yml"

def write-docker-service [name: string, service_config: record] {
  let c = $env.node_config
  let content = if ($dc_file | path exists) {
    open $dc_file
  } else {}

  let srv = ($service_config | merge {
    restart: "always"
    user: $"${RECALL_NODE_USER:-(id -u):(id -g)}"
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
        } | set-field auth_token $env.node_config.parent_endpoint.token?)
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

# Updates the input record if value is not empty and applies the transform if not empty.
def set-field [path: cell-path, value, transform?: closure] {
  if ($value | is-empty) {
    $in
  } else {
    let val = (if ($transform | is-empty) { $value } else { do $transform })
    $in | upsert $path $val
  }
}

export def init-docker-compose [] {
  let c = $env.node_config

  {
    name: $c.project_name
    networks: {
      default: {
        name: $c.project_name
        ipam: {
          config: [
            { subnet: $c.networking.docker_network_subnet }
          ]
        }
      }
    }
  } | save -f $dc_file
}

export def configure-ipc-cli [] {
  mkdir /workdir/ipc
  ipc-config "/workdir/ipc" | save -f "/workdir/ipc/config.toml"
  write-ipc-key /workdir/ipc $env.node_config.node_private_key
}

export def configure-cometbft [] {
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

  cometbft init --home /workdir/cometbft o> /dev/null
  fendermint key into-tendermint -s "/workdir/fendermint/keys/validator.sk" -o "/workdir/cometbft/config/priv_validator_key.json"

  open "/repo/config/services/cometbft.config.toml" | merge deep {
    proxy_app: $"tcp://($c.project_name)-fendermint-1:26658"
    moniker: $c.node_name
    p2p: {
      external_address: (if ($c.networking.advertised_external_ip? | is-empty) {""} else {$"($c.networking.advertised_external_ip):($c.networking.external_ports.cometbft)"})
      persistent_peers: ($c.network.endpoints.cometbft_persistent_peers | str join ",")
    }
    statesync: (statesync)
  } | save -f /workdir/cometbft/config/config.toml

  write-docker-service "cometbft" {
    image: $c.images.cometbft
    command: "run --home /cometbft --log_level=consensus:error,state:error,txindex:error"
    user: "root"
    volumes: [ "./cometbft:/cometbft" ]
  }
}

export def configure-fendermint [] {
  mkdir "/workdir/fendermint/config"
  let c = $env.node_config

  # Create keys
  do {
    let fendermint_keys_dir = "/workdir/fendermint/keys"
    mkdir $fendermint_keys_dir
    let eth_pk = $"($fendermint_keys_dir)/eth_pk"
    $c.node_private_key | save -f $eth_pk

    # Validator's key
    fendermint key from-eth -s $eth_pk -n validator -o $fendermint_keys_dir
    rm $eth_pk

    # Network key
    if not ($"($fendermint_keys_dir)/network.pk" | path exists) {
      fendermint key gen --name network --out-dir $fendermint_keys_dir
    }
  }

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
      } | set-field parent_http_auth_token $c.parent_endpoint.token?)
    }
  } |
    set-field resolver.discovery.static_addresses $c.network.endpoints.fendermint_seeds? |
    save -f "/workdir/fendermint/config/default.toml"

  write-docker-service "fendermint" {
    image: $c.images.fendermint
    command: "run"
    volumes: [
      "./fendermint:/data"
      $"($c.datadir)/iroh-fendermint:/iroh-data"
    ]
    environment: {
      FM_CONFIG_DIR: "/data/config"
      FM_NETWORK: $c.network.address_network
      IROH_RPC_ADDR: "0.0.0.0:4919"
      IROH_PATH: "/iroh-data"
      FM_TRACING__CONSOLE__LEVEL: "info,fendermint=debug,recall_kernel=debug,recall_executor=debug,recall_syscalls=debug,iroh_manager=debug"
    }
  }
}

export def configure-ethapi [] {
  let c = $env.node_config

  write-docker-service "ethapi" {
    image: $c.images.fendermint
    command: "eth run"
    volumes: [
      "./fendermint:/data"
    ]
    depends_on: [ "fendermint" ]
    environment: {
      TENDERMINT_RPC_URL: $"http://($c.project_name)-cometbft-1:26657"
      TENDERMINT_WS_URL: $"ws://($c.project_name)-cometbft-1:26657/websocket"
      FM_ETH__METRICS__LISTEN__HOST: "0.0.0.0"
      FM_ETH__CORS__ALLOWED_ORIGINS: "*"
      FM_ETH__CORS__ALLOWED_METHODS: "GET,HEAD,OPTIONS,POST"
      FM_ETH__CORS__ALLOWED_HEADERS: "Accept,Authorization,Content-Type,Origin"
    }
  }
}

export def configure-objects [] {
  let c = $env.node_config

  write-docker-service "objects" {
    image: $c.images.fendermint
    command: "objects run"
    volumes: [
      "./fendermint:/data"
      $"($c.datadir)/iroh-objects:/iroh-data"
    ]
    depends_on: [ "fendermint" "cometbft" ]
    environment: {
      TENDERMINT_RPC_URL: $"http://($c.project_name)-cometbft-1:26657"
      FM_OBJECTS__METRICS__LISTEN__HOST: "0.0.0.0"
      FM_NETWORK: $c.network.address_network
      IROH_RESOLVER_RPC_ADDR: $"(service-ip "fendermint"):4919"
      IROH_PATH: /iroh-data
    }
  }
}

export def configure-recall-exporter [] {
  let c = $env.node_config

  write-docker-service "recall-exporter" {
    image: $c.images.recall_exporter
    depends_on: [ "ethapi" ]
    environment: ({
      METRICS_ADDRESS: "0.0.0.0:9010"
      VALIDATOR_ADDRESS: (cast wallet address $c.node_private_key)
      PARENT_CHAIN_RPC_URL: $c.parent_endpoint.url
      PARENT_CHAIN_SUBNET_CONTRACT_ADDRESS: $c.network.parent_chain.addresses.subnet_contract
      SUBNET_RPC_URL: $"http://($c.project_name)-ethapi-1:8545"
      SUBNET_GATEWAY_ADDRESS: "0x77aa40b105843728088c0132e43fc44348881da8" # this is fix
      SUBNET_MEMBERSHIP_CHECK_INTERVAL: "10m"
      SUBNET_STATS_CHECK_INTERVAL: "5m"
    } |
      set-field RELAYER_ADDRESS $c.relayer?.private_key? {cast wallet address $c.relayer.private_key} |
      set-field PARENT_CHAIN_RPC_BEARER_TOKEN $c.parent_endpoint.token? |
      set-field FAUCET_ADDRESS $c.network.subnet.addresses?.faucet_contract? |
      set-field SUBNET_BLOB_MANAGER_CONTRACT_ADDRESS $c.network.subnet.addresses?.blob_manager?
    )
  }
}

const prom_targets_dir = "/workdir/prometheus/etc/targets"
export def configure-prometheus [] {
  rm -rf $prom_targets_dir
  rm -rf "/workdir/prometheus/etc/rules"
  mkdir $prom_targets_dir
  mkdir "/workdir/prometheus/etc/rules"
  mkdir "/workdir/prometheus/data"

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

  write-docker-service "prometheus" {
    image: $c.images.prometheus
    volumes: [
      "./prometheus/etc:/etc/prometheus"
      "./prometheus/data:/prometheus"
    ]
    command: ([
      "--config.file=/etc/prometheus/config.yml"
      "--storage.tsdb.retention.time=10m"
    ] | str join " ")
    ports: (if ($c.prometheus.bind_address? | is-empty) {[]} else {[$"($c.prometheus.bind_address):9090"]})
  }

  if ($c.prometheus?.external_network? | is-not-empty) {
    open $dc_file | merge deep {
      networks: {
        prometheus: {
          name: $c.prometheus.external_network
          external: true
        }
      }
      services: {
        prometheus: {
          networks: {
            prometheus: {}
          }
        }
      }
    } | save -f $dc_file
  }
}

export def configure-relayer [] {
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
      "./relayer:/relayer"
    ]
    environment: {
      subnet_id: $c.network.subnet.subnet_id
      relayer_address: $addr
      relayer_checkpoint_interval_sec: $c.services.relayer_checkpoint_interval_sec
    }
    depends_on: [ "fendermint" ]
  }

  # metrics
  [{
    targets: [ $"($c.project_name)-relayer-1:9184"]
  }] | save -f $"($prom_targets_dir)/relayer.json"
}

export def configure-registrar [] {
  let c = $env.node_config

  write-docker-service "registrar" {
    image: $c.images.registrar
    depends_on: [ "ethapi" ]
    environment: {
      PRIVATE_KEY: $c.registrar.faucet_owner_private_key
      FAUCET_ADDRESS: $c.network.subnet.addresses.faucet_contract
      TRUSTED_PROXY_IPS: ($c.registrar.trusted_proxy_ips | str join ",")
      EVM_RPC_URL: $"http://($c.project_name)-ethapi-1:8545"
      LISTEN_HOST: "0.0.0.0"
      LISTEN_PORT: "8080"
      METRICS_LISTEN_ADDRESS: "0.0.0.0:9090"
      TS_SECRET_KEY: $c.registrar.turnstile_secret_key
    }
  }

  # metrics
  [{
    targets: [ $"($c.project_name)-registrar-1:9090"]
  }] | save -f $"($prom_targets_dir)/registrar.json"
}

export def configure-recall-s3 [] {
  let c = $env.node_config
  mkdir /workdir/recall-s3
  write-docker-service "recall-s3" {
    image: $c.images.recall_s3
    depends_on: [
      "cometbft"
      "objects"
    ]
    volumes: [
      "./recall-s3:/recall-s3"
    ]
    environment: {
      HOST: 0.0.0.0
      PORT: "8014"
      HOME: "/recall-s3"
      ACCESS_KEY: $c.recall_s3.access_key
      SECRET_KEY: $c.recall_s3.secret_key
      DOMAIN_NAME: $c.recall_s3.domain
      METRICS_LISTEN_ADDRESS: "0.0.0.0:9090"
      RUST_LOG: recall_s3=info
      NETWORK: custom
      SUBNET_ID: $c.network.subnet.subnet_id
      RPC_URL: $"http://($c.project_name)-cometbft-1:26657"
      OBJECT_API_URL: $"http://($c.project_name)-objects-1:8001"
    }
  }

  # metrics
  [{
    targets: [ $"($c.project_name)-recall-s3-1:9090"]
  }] | save -f $"($prom_targets_dir)/recall-s3.json"
}

export def configure-http-network [] {
  let c = $env.node_config

  let http_services = ([
    {name: cometbft only_if: true}
    {name: ethapi only_if: true}
    {name: objects only_if: true}
    {name: registrar only_if: $c.registrar.enable}
    {name: recall-s3 only_if: $c.recall_s3.enable}
    ] | where only_if == true | each {[$in.name {
      networks: {
        external-http: {}
      }
    }]} | into record)

  open $dc_file | merge deep {
    networks: {
      external-http: {
        name: $c.http_docker_network.network_name
        external: true
      }
    }
    services: $http_services
  } | save -f $dc_file
}

export def configure-external-ports [] {
  let c = $env.node_config
  let ip = $c.networking.host_bind_ip
  let ports = $c.networking.external_ports

  open $dc_file | merge deep {
    services: {
      cometbft: {
        ports: [ $"($ip):($ports.cometbft):26656" ]
      }
      fendermint: {
        ports: [
          $"($ip):($ports.fendermint):26655"
          $"($ip):($ports.fendermint_iroh):11204/udp"
        ]
      }
      objects: {
        ports: [ $"($ip):($ports.objects_iroh):11204/udp" ]
      }
    }
  } | save -f $dc_file
}

export def configure-localnet [] {
  let c = $env.node_config

  let srv = ([
    {name: cometbft only_if: true}
    {name: fendermint only_if: true}
    {name: ethapi only_if: true}
    {name: objects only_if: true}
    {name: recall-exporter only_if: true}
    {name: relayer only_if: $c.relayer.enable}
  ] | where only_if == true | each {[$in.name {
    networks: {
      localnet: {}
    }
  }]} | into record)

  let cli_binds = (if ($c.localnet.cli_bind_host? | is-empty) {{}} else {
    let cli_host = $"${LOCALNET_CLI_BIND_HOST:-($c.localnet.cli_bind_host)}"
    {
      cometbft: {
        ports: [ $"($cli_host):26657:26657" ]
      }
      ethapi: {
        ports: [ $"($cli_host):8645:8545" ]
      }
      objects: {
        ports: [ $"($cli_host):8001:8001" ]
      }
    }
  })

  open $dc_file | merge deep {
    networks: {
      localnet: {
        name: $c.localnet.network
        external: true
      }
    }
    services: ($srv | merge deep $cli_binds)
  } | save -f $dc_file
}

export def write-node-tools [] {
  mkdir /workdir/scripts
  let c = $env.node_config
  $c | save -f /workdir/scripts/config.yml

  cp /repo/scripts/node-tools.nu /workdir/scripts/node-tools
  cp /repo/scripts/util.nu /workdir/scripts/

  let tools_file = "/workdir/node-tools"
  [
    "#!/usr/bin/env bash"
    "set -e"
    '[ -t 0 ] && tty_flag="-it" || tty_flag=""'
    $"docker run --name node-tools --rm $tty_flag -v ($env.USER_SPACE_WORKDIR):/workdir --network ($c.project_name) ($env.TOOLS_IMAGE) /workdir/scripts/node-tools $@"
    ""
  ] | str join "\n" | save -f $tools_file
  chmod +x $tools_file
}
