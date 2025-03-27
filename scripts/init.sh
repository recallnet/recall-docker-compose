#!/usr/bin/env bash

set -euo pipefail

current_dir=$(dirname $0)
repo_dir=$(cd $current_dir/..; pwd)
source $current_dir/read-config.sh

# set -x
mkdir -p $workdir
workdir=$(cd $workdir; pwd)
log_file=$workdir/init.log
utils_image=recall-init-utils
logged_done="true"

function run-docker {
  set +u
  flags=""
  if [ ! -z "$external_default_network" ]; then
    flags="--network $external_default_network"
  fi
  set -u

  if [ -t 1 ]; then
    # Terminal is interactive
    docker run --name recall-init --rm -it $flags "$@"
  else
    # Non-interactive environment (CI)
    docker run --name recall-init --rm $flags "$@"
  fi
}

function log-job-name {
  [ $logged_done == "true" ] || log-done
  echo -n "=== $1..." | tee -a $log_file
  echo "" >> $log_file
  logged_done="false"
}
function log-done {
  echo "✅"
}

rm -f $log_file
set +e
docker rm -f recall-init > /dev/null 2>&1
set -e

log-job-name "Build utils image"
if ! docker buildx ls | grep -q "multi-arch-builder"; then
  docker buildx create --name multi-arch-builder --driver docker-container
fi
# Cannot use --load for multi-arch builds, so we build and load for each arch separately.
docker buildx build --builder=multi-arch-builder --platform linux/amd64 --load -t $utils_image:amd64 --build-arg fendermint_image=$fendermint_image -f $current_dir/utils.Dockerfile $current_dir >> $log_file 2>&1
docker buildx build --builder=multi-arch-builder --platform linux/arm64 --load -t $utils_image:arm64 --build-arg fendermint_image=$fendermint_image -f $current_dir/utils.Dockerfile $current_dir >> $log_file 2>&1

platform=$(uname -m | sed -e 's/x86_64/amd64/g' -e 's/aarch64/arm64/g')

log-job-name "Validate config"
run-docker -v $repo_dir:/repo:ro $utils_image:$platform /repo/scripts/validate-config.sh

log-job-name "Init CometBFT"
run-docker --user root -v $workdir/cometbft:/cometbft --entrypoint bash $cometbft_image -c "cometbft init --home /cometbft" >> $log_file 2>&1

log-job-name "Download genesis file"
if [ "$cometbft_statesync_enable" == "true" ]; then
  run-docker -v $workdir/cometbft:/cometbft -v $repo_dir:/repo:ro $utils_image:$platform /repo/scripts/download-genesis.sh >> $log_file 2>&1
else
  run-docker -v $workdir/cometbft:/cometbft -v $repo_dir:/repo:ro --entrypoint bash $fendermint_image /repo/scripts/download-genesis.sh >> $log_file 2>&1
fi

log-job-name "Generate node keys"
run-docker -v $workdir:/workdir -v $repo_dir:/repo:ro --entrypoint bash $fendermint_image /repo/scripts/set-up-keys.sh >> $log_file 2>&1

log-job-name "Write config files"
run-docker -v $workdir:/workdir -v $repo_dir:/repo:ro $utils_image:$platform /repo/scripts/write-configs.sh >> $log_file 2>&1

log-done
