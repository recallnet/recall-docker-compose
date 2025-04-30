#!/usr/bin/env nu

# This scripts prints commands for the recall node initialization.
def main [
  repo_dir: string, # path to the current git repository in user space
] {
  let cfg = (open "/repo/config/node-default.toml")

  let scripts_dir = ($repo_dir | path join "scripts")
  let init_image = $"recall-init:($cfg.images.fendermint | split row ':' | get 1)"

  let args = $"--build-arg fendermint_image=($cfg.images.fendermint) --build-arg cometbft_image=($cfg.images.cometbft)"
  [
    "set -eu"
    $"docker build -t ($init_image) ($args) -f ($scripts_dir)/init.Dockerfile ($scripts_dir)"
    $"docker run --rm -it -v ($repo_dir):/repo ($init_image) /repo/scripts/init.nu"
  ] | str join "; "

}
