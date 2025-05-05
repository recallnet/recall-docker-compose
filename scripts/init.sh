#!/usr/bin/env bash

set -euo pipefail

current_dir=$(dirname $0)
repo_dir=$(cd $current_dir/..; pwd)

echo -n "Building init docker images... "
docker build -q -t recall-nushell -f $current_dir/nushell.Dockerfile $current_dir > /dev/null

source <(docker run --rm -it -v $repo_dir:/repo recall-nushell /repo/scripts/bootstrap.nu $repo_dir)
