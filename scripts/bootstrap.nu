#!/usr/bin/env nu

# This scripts prints commands for the recall node initialization.
def main [
  repo_dir: string, # path to the current git repository in user space
] {
  let cfg = (open "/repo/config/node-default.toml")

  let scripts_dir = ($repo_dir | path join "scripts")
  let init_image = $"recall-init:($cfg.images.fendermint | split row ':' | get 1)"

  let workdir = (get-workdir $repo_dir $cfg)
  let args = $"--build-arg fendermint_image=($cfg.images.fendermint) --build-arg cometbft_image=($cfg.images.cometbft)"
  let mounts = $"-v ($repo_dir):/repo -v ($workdir):/workdir"
  [
    "set -eu"
    $"docker build -q -t ($init_image) ($args) -f ($scripts_dir)/init.Dockerfile ($scripts_dir) > /dev/null"
    $"docker run --rm -it ($mounts) ($init_image) /repo/scripts/init.nu"
  ] | str join "; "
}

def get-workdir [repo_dir: string, cfg: record] {
  let node_cfg = "/repo/config/node.toml"
  let cfg = if ($node_cfg | path exists) {
    $cfg | merge deep (open $node_cfg)
  } else $cfg

  let workdir = $cfg.directories.workdir
  if $workdir =~ "^/" {$workdir} else {$repo_dir | path join $workdir | path expand}
}
