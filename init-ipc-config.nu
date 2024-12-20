let cfg = (open /scripts/network-config.toml)

const dest = "/ipc/config.toml"
if ($dest | path exists) {
  print "ipc/config.toml already exists"
  exit 0
}

{
  keystore_path: "/ipc"
  subnets: [
    {
      id: "/r314159"
      config: {
        network_type: "fevm"
        provider_http: $cfg.parent_endpoint
        auth_token: $cfg.parent_endpoint_token
        gateway_addr: $cfg.parent_gateway_address
        registry_addr: $cfg.parent_registry_address
      }
    }
    {
      id: $cfg.subnet_id
      config: {
        network_type: "fevm"
        provider_http: "http://ethapi:8545"
        gateway_addr: "0x77aa40b105843728088c0132e43fc44348881da8"
        registry_addr: "0x74539671a1d2f1c8f200826baba665179f53a1b7"
      }
    }
  ]
} | to toml | save $dest

print $"created ($dest)"
