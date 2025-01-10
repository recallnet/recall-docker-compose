#!/usr/bin/env bash

set -e

cmd="$@"
export COMPOSE_ENV_FILES="./config/node-default.env,./config/node.env"

function set_compose_files {
  source ./config/node-default.env
  source ./config/node.env
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
    echo "     Initializes the current docker compose folder. Call it after you have edited ./config/node.env"
    echo "  ./run.sh [args]"
    echo "     Invokes docker compose \$args"
    ;;
    
  init)
    export COMPOSE_FILE="./docker-compose.init.yml"
    trap "docker compose down" EXIT
    docker compose up --abort-on-container-failure
    ;;

  *)
    set_compose_files
    docker compose $cmd
    ;;
esac


