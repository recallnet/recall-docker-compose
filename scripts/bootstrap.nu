#!/usr/bin/env nu

use util.nu

# This scripts prints commands for the recall node initialization.
def main [
  repo_dir: string, # path to the current git repository in user space
  workdir: string, # absolute path
] {
  let c = (util read-config)

  let scripts_dir = ($repo_dir | path join "scripts")
  let tools_image = if ($c.images.fendermint | str contains ":") {
    $"recall-tools:($c.images.fendermint | split row ':' | get 1)"
  } else "recall-tools"

  let build_args = $"--build-arg fendermint_image=($c.images.fendermint) --build-arg cometbft_image=($c.images.cometbft)"
  let run_args = [
    -v $"($repo_dir):/repo"
    -v $"($workdir):/workdir"
    -e $"TOOLS_IMAGE=($tools_image)"
    -e $"USER_SPACE_WORKDIR=($workdir)"
    ...(if $c.localnet.enable { [--network $c.localnet.network] } else [])
    -u "$(id -u):$(id -g)"
  ] | str join " "

  $"
    set -eu
    docker build -q -t ($tools_image) ($build_args) -f ($scripts_dir)/tools.Dockerfile ($scripts_dir) > /dev/null
    docker run --rm $tty_flag ($run_args) ($tools_image) /repo/scripts/init.nu
    rm -f ($workdir)/init.sh

    function mkDataDir {
      \(
        cd ($workdir)
        mkdir -p ($c.datadir)/$1
        chown (id -u):(id -g) ($c.datadir)/$1
      )
    }

    mkDataDir iroh-fendermint
    mkDataDir iroh-objects
  " | save -f "/workdir/init.sh"
}
