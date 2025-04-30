#!/usr/bin/env nu

use genesis.nu

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

validate-config
step "Init CometBFT" { cometbft init --home /workdir/cometbft }
step "Download genesis" { genesis download }

# $env.node_config | to yaml
