#!/usr/bin/env bash

set -e

cmd="$1"

source ./scripts/read-config.sh

function set_compose_files {
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
    echo "  ./run.sh join-subnet <collateral in whole tHOKU units>"
    echo "     Join the subnet with the specified collateral"
    echo "  ./run.sh node-info"
    echo "     Print node info"
    echo "  ./run.sh ipc-cli [args]"
    echo "     Call ipc-cli \$args"
    echo "  ./run.sh [args]"
    echo "     Call docker compose \$args"
    ;;
    
  init)
    export COMPOSE_FILE="./docker-compose.init.yml"
    trap "docker compose down" EXIT
    docker compose up --build --abort-on-container-failure
    ;;

  create-key)
    docker run --name create-key --rm -v $PWD/scripts/create-key.sh:/bin/create-key.sh --entrypoint /bin/create-key.sh $fendermint_image
    ;;

  join-subnet)
    addr=$(jq -r '.[].address' < $workdir/ipc/evm_keystore.json)
    docker run --name ipc-cli --rm -it --network $project_name -v $PWD/$workdir/ipc:/fendermint/.ipc $fendermint_image ipc-cli subnet join --from $addr --subnet $subnet_id --collateral $2
    ;;

  node-info)
    # set -x
    cometbft_id=$(docker exec ${project_name}-cometbft-1 cometbft show-node-id)
    fendermint_id=$(docker exec ${project_name}-fendermint-1 fendermint key show-peer-id --public-key /data/keys/network.pk)
    echo "cometbft API URL: https://${dns_api}:443"
    echo "commetbft: $cometbft_id@${dns_api}:26656"
    echo "fendermint: /dns/$dns_api/tcp/26655/p2p/$fendermint_id"
    ;;

  ipc-cli)
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


