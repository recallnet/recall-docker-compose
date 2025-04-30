#!/usr/bin/env nu

def read-config [] {
  let config = open "/repo/config/node-default.toml" |
    merge deep (open "/repo/config/node.toml")
  let network = (open $"/repo/config/network-($config.network_name).toml")

  $config | merge { network: $network }
}

let config = (read-config)

def parent-rpc-url [] {
  if ("token" in $config.parent_endpoint) {
    $"($config.parent_endpoint.url)?token=($config.parent_endpoint.token)"
  } else $config.parent_endpoint.url
}

def validate-config [] {
  print -n "Checking parent chain RPC endpoint... "
  let result = (cast chain-id --rpc-url (parent-rpc-url) | complete)
  if $result.exit_code == 0 {
    print "✅"
  } else {
    print "❌"
    print $result.stderr
    exit 1
  }

  if ("evm_rpc_url" in $config.network.endpoints) {
    print -n "Checking wallet balance on subnet... "
    let address = (cast wallet address $config.node_private_key)
    if (cast balance --rpc-url $config.network.endpoints.evm_rpc_url $address | into int) == 0 {
      print "❌"
      print $"ERROR: no funds on subnet for the node address ($address)"
      exit 1
    } else {
      print "✅"
    }
  }
}

validate-config


# $config | to yaml
