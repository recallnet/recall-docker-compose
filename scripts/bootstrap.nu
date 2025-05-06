#!/usr/bin/env nu

use util.nu

# This scripts prints commands for the recall node initialization.
def main [
  repo_dir: string, # path to the current git repository in user space
  workdir: string, # absolute path
] {
  let cfg = (util read-config)

  let scripts_dir = ($repo_dir | path join "scripts")
  let tools_image = $"recall-tools:($cfg.images.fendermint | split row ':' | get 1)"

  let build_args = $"--build-arg fendermint_image=($cfg.images.fendermint) --build-arg cometbft_image=($cfg.images.cometbft)"
  let args = [
    -v $"($repo_dir):/repo"
    -v $"($workdir):/workdir"
    -e $"TOOLS_IMAGE=($tools_image)"
    -e $"USER_SPACE_WORKDIR=($workdir)"
  ] | str join " "

  [
    "set -eu"
    $"docker build -q -t ($tools_image) ($build_args) -f ($scripts_dir)/tools.Dockerfile ($scripts_dir) > /dev/null"
    $"docker run --rm -it ($args) ($tools_image) /repo/scripts/init.nu"
  ] | str join "; "
}
