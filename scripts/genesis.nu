
const genesis_dir = "/workdir/genesis"
const dest = ($genesis_dir | path join "genesis.json")

const raw = ($genesis_dir | path join "genesis.raw.json")
const sealed = ($genesis_dir | path join "genesis.sealed.json")

export def download [] {
  if ($dest | path exists) { return }

  $env.FM_NETWORK = $env.node_config.network.address_network
  mkdir $genesis_dir

  if $env.node_config.services.cometbft_statesync_enable {
    download-from-peer
  } else {
    download-from-parent-chain
  }

  cp $dest /workdir/cometbft/config/
}

def download-from-parent-chain [] {
  let net = $env.node_config.network
  fendermint genesis ...[
    --genesis-file $raw
    ipc from-parent
    --subnet-id $net.subnet.subnet_id
    --parent-endpoint $env.node_config.parent_endpoint.url
    ...(if "token" in $env.node_config.parent_endpoint {[--parent-auth-token $env.node_config.parent_endpoint.token]} else [])
    --parent-gateway $net.parent_chain.addresses.gateway
    --parent-registry $net.parent_chain.addresses.registry
  ]

  fendermint genesis --genesis-file $raw set-eam-permissions --mode unrestricted

  if "chain_id" in $net.subnet {
    fendermint genesis --genesis-file $raw set-chain-id --chain-id $net.subnet.chain_id
  }

  fendermint genesis ...[
    --genesis-file $raw
    ipc seal-genesis
    --builtin-actors-path /fendermint/bundle.car
    --custom-actors-path /fendermint/custom_actors_bundle.car
    --artifacts-path /fendermint/contracts
    --output-path $sealed
  ]

  fendermint genesis ...[
    --genesis-file $raw
    into-tendermint
    --app-state $sealed
    --out $dest
  ]
}

def download-from-peer [] {
  let net = $env.node_config.network

  let remote = $net.endpoints.cometbft_rpc_servers.0
  mut total = 100
  mut ix = 0
  let genesis_tmp = ($genesis_dir | path join "genesis.tmp")

  rm -f $genesis_tmp
  while $ix < $total {
    let chunk = (http get $"($remote)/genesis_chunked?chunk=($ix)")
    if $total == 100 {
      $total = ($chunk.result.total | into int)
    }
    $chunk.result.data | decode base64 | save -a $genesis_tmp
    $ix = ($ix + 1)
  }
  mv $genesis_tmp $dest
}
