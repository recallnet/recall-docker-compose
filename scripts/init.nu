#!/usr/bin/env nu

use genesis.nu
use service-configs.nu

def read-config [] {
  let config = open "/repo/config/node-default.toml" |
    merge deep (open "/repo/config/node.toml")
  let network = (open $"/repo/config/network-($config.network_name).toml")

  $config | merge { network: $network }
}

$env.node_config = (read-config)

def parent-rpc-url [] {
  if ("token" in $env.node_config.parent_endpoint) {
  $"($env.node_config.parent_endpoint.url)?token=($env.node_config.parent_endpoint.token)"
  } else $env.node_config.parent_endpoint.url
}

def step [name: string, fn: closure] {
  print -n $"($name)... "
  let result = (do $fn | default {})
  if "err" in $result {
    print "❌"
    print $"ERROR: ($result.err)"
    exit 15
  } else {
    print "✅"
  }
}

def validate-config [] {
  step "Checking parent chain RPC endpoint" {
    let result = (cast chain-id --rpc-url (parent-rpc-url) | complete)
    if $result.exit_code != 0 {
      {err: $result.stderr}
    }
  }

  if ("evm_rpc_url" in $env.node_config.network.endpoints) {
    step "Checking wallet balance on subnet" {
      let address = (cast wallet address $env.node_config.node_private_key)
      if (cast balance --rpc-url $env.node_config.network.endpoints.evm_rpc_url $address | into int) == 0 {
        { err: $"ERROR: no funds on subnet for the node address ($address)" }
      }
    }
  }
}

def set-up-keys [] {
  let cometbft_dir = "/workdir/cometbft"
  let fendermint_dir = "/workdir/fendermint"
  let relayer_dir = "/workdir/relayer"
  let fendermint_keys_dir = $"($fendermint_dir)/keys"
  let ipc_dir = "/workdir/ipc"

  # === Fendermint
  mkdir $fendermint_keys_dir

  let eth_pk = "/tmp/key"
  $env.node_config.node_private_key | save -f $eth_pk

  # Validator's key
  fendermint key from-eth -s $eth_pk -n validator -o $fendermint_keys_dir
  rm $eth_pk

  # Network key
  if not ($"($fendermint_keys_dir)/network.pk" | path exists) {
    fendermint key gen --name network --out-dir $fendermint_keys_dir
  }

  # === CometBFT
  fendermint key into-tendermint -s $"($fendermint_keys_dir)/validator.sk" -o $"($cometbft_dir)/config/priv_validator_key.json"

  # === ipc-cli
  mkdir $ipc_dir
  let cfg = $"($ipc_dir)/config.toml"
  {keystore_path: $ipc_dir} | save -f $cfg

  ipc-cli --config-path $cfg wallet import --wallet-type evm --private-key $env.node_config.node_private_key o> /dev/null

  # === Relayer
  if $env.node_config.relayer.enable {
    mkdir $"($relayer_dir)/ipc"
    let cfg = $"($relayer_dir)/ipc/config.toml"
    {keystore_path: $"($relayer_dir)/ipc"} | save -f $cfg
    ipc-cli --config-path $cfg wallet import --wallet-type evm --private-key $env.node_config.node_private_key o> /dev/null
  }
}

validate-config
step "Init CometBFT" { cometbft init --home /workdir/cometbft }
step "Download genesis" { genesis download }
step "Set up node keys" { set-up-keys }

step "Write ipc-cli config" { service-configs write-ipc-cli }
step "Write CometBFT config" { service-configs write-cometbft  }
step "Write fendermint config" { service-configs write-fendermint }
step "Write prometheus config" { service-configs write-prometheus }
