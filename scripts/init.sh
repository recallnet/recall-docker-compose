#!/usr/bin/env bash

set -euo pipefail

current_dir=$(dirname $0)
repo_dir=$(cd $current_dir/..; pwd)

echo -n "Building init docker images... "
docker build -q -t recall-nushell -f $current_dir/nushell.Dockerfile $current_dir > /dev/null

source <(docker run --rm -it -v $repo_dir:/repo recall-nushell /repo/scripts/bootstrap.nu $repo_dir)


exit 2
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
  if [ ! -z "$localnet_network" ]; then
    flags="--network $localnet_network"
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
docker rm -f recall-init &> /dev/null
set -e

log-job-name "Build utils image"
docker build -t $utils_image --build-arg fendermint_image=$fendermint_image -f $current_dir/utils.Dockerfile $current_dir &>> $log_file

log-job-name "Validate config"
run-docker -v $repo_dir:/repo:ro $utils_image /repo/scripts/validate-config.sh

log-job-name "Init CometBFT"
run-docker --user root -v $workdir/cometbft:/cometbft --entrypoint bash $cometbft_image -c "cometbft init --home /cometbft" &>> $log_file

log-job-name "Download genesis file"
if [ "$cometbft_statesync_enable" == "true" ]; then
  run-docker -v $workdir/cometbft:/cometbft -v $repo_dir:/repo:ro $utils_image /repo/scripts/download-genesis.sh &>> $log_file
else
  run-docker -v $workdir/cometbft:/cometbft -v $repo_dir:/repo:ro --entrypoint bash $fendermint_image /repo/scripts/download-genesis.sh &>> $log_file
fi

log-job-name "Generate node keys"
run-docker -v $workdir:/workdir -v $repo_dir:/repo:ro --entrypoint bash $fendermint_image /repo/scripts/set-up-keys.sh &>> $log_file

log-job-name "Write config files"
run-docker -v $workdir:/workdir -v $repo_dir:/repo:ro $utils_image /repo/scripts/write-configs.sh &>> $log_file

log-done
