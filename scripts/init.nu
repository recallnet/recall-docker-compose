#!/usr/bin/env nu

use genesis.nu
use service-configs.nu
use util.nu

def step [name: string, fn: closure] {
  print -n $"($name)... "
  let result = (do $fn | default {})
  if "err" in $result {
    print "❌"
    print $"ERROR: ($result.err)"
    exit 15
  } else {
    print $"(ansi green_bold)✔(ansi reset)"
  }
}

def validate-config [] {
  let c = $env.node_config

  step "Checking parent chain RPC endpoint" {
    let result = (cast chain-id --rpc-url (util parent-rpc-url $c.parent_endpoint) | complete)
    if $result.exit_code != 0 {
      {err: $result.stderr}
    }
  }

  if ("evm_rpc_url" in $c.network.endpoints) {
    step "Checking wallet balance on subnet" {
      let address = (cast wallet address $c.node_private_key)
      if (cast balance --rpc-url $c.network.endpoints.evm_rpc_url $address | into int) == 0 {
        { err: $"ERROR: no funds on subnet for the node address ($address)" }
      }
    }
  }
}

def main [] {
  $env.node_config = (util read-config)
  let c = $env.node_config

  # Printing success for docker image build.
  print $"(ansi green_bold)✔(ansi reset)"

  validate-config
  step "Init docker-compose" { service-configs init-docker-compose }
  step "Configuring fendermint" { service-configs configure-fendermint }
  step "Configuring CometBFT" { service-configs configure-cometbft }
  step "Downloading genesis" { genesis download }
  step "Configuring ethapi" { service-configs configure-ethapi }
  step "Configuring objects" { service-configs configure-objects }
  step "Configuring recall-exporter" { service-configs configure-recall-exporter }
  step "Configuring prometheus" { service-configs configure-prometheus }
  if $c.relayer.enable {
    step "Configuring relayer" { service-configs configure-relayer }
  }
  if $c.recall_s3.enable {
    step "Configuring recall-s3" { service-configs configure-recall-s3 }
  }
  if $c.registrar.enable {
    step "Configuring registrar" { service-configs configure-registrar }
  }
  if ($c.http_docker_network?.network_name? | is-not-empty) {
    step "Configuring HTTP network" { service-configs configure-http-network }
  }
  if ($c.networking.host_bind_ip? | is-not-empty) {
    step "Configuring external ports" { service-configs configure-external-ports }
  }
  if $c.localnet.enable {
    step "Configuring localnet" { service-configs configure-localnet }
  }
  step "Configuring ipc-cli" { service-configs configure-ipc-cli }
  step "Writing node tools" { service-configs write-node-tools }
}
