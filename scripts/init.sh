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
  docker run --name recall-init --rm -it $flags "$@"
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
