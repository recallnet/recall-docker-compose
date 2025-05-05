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

}

let c = $env.node_config

# validate-config
# step "Init CometBFT" { cometbft init --home /workdir/cometbft }
# step "Download genesis" { genesis download }
# step "Set up node keys" { set-up-keys }
step "Configure ipc-cli" { service-configs write-ipc-cli }
# step "Configure CometBFT" { service-configs write-cometbft  }
# step "Configure fendermint" { service-configs write-fendermint }
# step "Configure prometheus" { service-configs write-prometheus }
if $c.relayer.enable {
  step "Configure relayer" { service-configs write-relayer }
}
if $c.recall_s3.enable {
  step "Configure recall-s3" { service-configs write-recall-s3 }
}
if $c.registrar.enable {
  step "Configure registrar" { service-configs write-registrar }
}
