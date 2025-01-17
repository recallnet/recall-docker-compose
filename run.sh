#!/usr/bin/env bash

set -e

cmd="$1"
export COMPOSE_ENV_FILES="./config/node-default.env,./config/node.env"

function source_config {
  source ./config/node-default.env
  source ./config/node.env
  source ./config/network-${network_name}.env
}

function set_compose_files {
  source_config
  COMPOSE_FILE=./docker-compose.run.yml
  [ "$enable_relayer" == "true" ] && COMPOSE_FILE="$COMPOSE_FILE:./config/optional/relayer.yml"
  [ "$enable_faucet" == "true" ] && COMPOSE_FILE="$COMPOSE_FILE:./config/optional/faucet.yml"
  [ "$enable_basin_s3" == "true" ] && COMPOSE_FILE="$COMPOSE_FILE:./config/optional/basin-s3.yml"
  export COMPOSE_FILE
}

case ${cmd:-"none"} in
  none)
    echo "Usage: "
    echo "  ./run.sh init"
    echo "     Initialize the current docker compose folder. Call it after you have edited ./config/node.env"
    echo "  ./run.sh create-key"
    echo "     Create a new key"
    echo "  ./run.sh join-subnet <collateral in whole HOKU units>"
    echo "     Join the subnet with the specified collateral"
    echo "  ./run.sh ipc-cli [args]"
    echo "     Call ipc-cli \$args"
    echo "  ./run.sh [args]"
    echo "     Call docker compose \$args"
    ;;
    
  init)
    export COMPOSE_FILE="./docker-compose.init.yml"
    trap "docker compose down" EXIT
    docker compose up --abort-on-container-failure
    ;;

  create-key)
    source_config
    docker run --name create-key --rm -v $PWD/init/create-key.sh:/bin/create-key.sh --entrypoint /bin/create-key.sh $fendermint_image
    ;;

  join-subnet)
    source_config
    addr=$(jq -r '.[].address' < $workdir/ipc/evm_keystore.json)
    docker run --name ipc-cli --rm -it --network $project_name -v $PWD/$workdir/ipc:/fendermint/.ipc $fendermint_image ipc-cli subnet join --from $addr --subnet $subnet_id --collateral $2
    ;;

  ipc-cli)
    source_config
    set +e
    docker_network=""
    docker network ls | grep $project_name > /dev/null
    [ $? == 0 ] && docker_network="--network $project_name"
    set -e
    docker run --name ipc-cli --rm -it $docker_network -v $PWD/$workdir/ipc:/fendermint/.ipc $fendermint_image "$@"
    ;;

  *)
    set_compose_files
    docker compose "$@"
    ;;
esac


