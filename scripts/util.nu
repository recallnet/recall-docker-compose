export def read-config [] {
  let config = open "/repo/config/node-default.toml" |
    merge deep (open "/repo/config/node.toml")
  let network = (open $"/repo/config/network-($config.network_name).toml")

  $config | merge { network: $network }
}

export def parent-rpc-url [parent_endpoint: record] {
  if ("token" in $parent_endpoint) {
    $"($parent_endpoint.url)?token=($parent_endpoint.token)"
  } else {
    $parent_endpoint.url
  }
}
