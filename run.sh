#!/usr/bin/env bash

set -e

cmd=$1
export COMPOSE_ENV_FILES="./config/node-default.env,./config/node.env"

function set_compose_files {
  source ./config/node-default.env
  source ./config/node.env
  COMPOSE_FILE=./docker-compose.run.yml
  if [ $enable_faucet == "true" ]; then
    COMPOSE_FILE="$COMPOSE_FILE:./config/optional/faucet.yml"
  fi
  if [ $enable_relayer == "true" ]; then
    COMPOSE_FILE="$COMPOSE_FILE:./config/optional/relayer.yml"
  fi
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


