use util.nu

def main [] {}

def read-config [] {
  open /workdir/scripts/config.yml
}

# Joins the subnet with the provided collateral amount.
def "main join-subnet" [
  collateral: int, # collateral in whole RECALL units
] {
  let c = (read-config)

  print "== Approving collateral"
  cast send ...[
    --private-key $c.node_private_key
    --rpc-url (util parent-rpc-url $c.parent_endpoint)
    --timeout 120
    --confirmations 10
    $c.network.parent_chain.addresses.supply_source
    'approve(address,uint256)' $c.network.parent_chain.addresses.subnet_contract ($collateral * 1e18)
  ]

  print "== Joining subnet"
  $env.IPC_CLI_CONFIG_PATH = "/workdir/ipc/config.toml"
  ipc-cli subnet join --from (cast wallet address $c.node_private_key) --subnet $c.network.subnet.subnet_id --collateral $collateral
}

# Print cometbft and fendermint peer IDs.
def "main show-peer-ids" [] {
  {
    cometbft_id: (cometbft --home /workdir/cometbft show-node-id)
    fendermint_id: (fendermint key show-peer-id --public-key /workdir/fendermint/keys/network.pk)
  } | to yaml
}

# Prints node status
def "main status" [] {
  let c = (read-config)
  let status = (http get $"http://($c.project_name)-cometbft-1:26657/status")
  $status.result.sync_info
    | select latest_block_height latest_block_time earliest_block_height earliest_block_time catching_up
    | merge { voting_power: $status.result.validator_info.voting_power }
    | to yaml
}
