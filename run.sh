#!/usr/bin/env bash

set -e

cmd="$1"


case ${cmd:-"none"} in
  none)
    echo "Usage: "
    echo "  ./run.sh init"
    echo "     Initialize the current docker compose folder. Call it after you have edited ./config/node.env"
    echo "  ./run.sh create-key"
    echo "     Create a new key"
    echo "  ./run.sh join-subnet <collateral in whole RECALL units>"
    echo "     Join the subnet with the specified collateral"
    echo "  ./run.sh node-info"
    echo "     Print node info"
    echo "  ./run.sh ipc-cli [args]"
    echo "     Call ipc-cli \$args"
    echo "  ./run.sh [args]"
    echo "     Call docker compose \$args"
    ;;

  init)
    ./scripts/init.sh
    ;;

  create-key)
    docker run --name create-key --rm -v $PWD/scripts/create-key.sh:/bin/create-key.sh --entrypoint /bin/create-key.sh $fendermint_image
    ;;

  join-subnet)
    addr=$(jq -r '.[].address' < $workdir/ipc/evm_keystore.json)
    private_key=0x$(jq -r '.[].private_key' < $workdir/ipc/evm_keystore.json)
    collateral=$2
    echo "== Approving collateral"
    docker run --name cast --rm -it ghcr.io/foundry-rs/foundry:latest "cast send \
      --private-key $private_key \
      --rpc-url $parent_endpoint${parent_endpoint_token:+"?token=$parent_endpoint_token"} \
      --timeout 120 \
      --confirmations 10 \
      $parent_supply_source_address 'approve(address,uint256)' $parent_subnet_contract_address $(($collateral * 10**18))"
    echo "== Joining subnet"
    docker run --name ipc-cli --rm -it --network $project_name -v $(cd $workdir; pwd)/ipc:/fendermint/.ipc $fendermint_image ipc-cli subnet join --from $addr --subnet $subnet_id --collateral $collateral
    ;;

  node-info)
    # set -x
    cometbft_id=$(docker exec ${project_name}-cometbft-1 cometbft show-node-id)
    fendermint_id=$(docker exec ${project_name}-fendermint-1 fendermint key show-peer-id --public-key /data/keys/network.pk)
    echo "cometbft_id: $cometbft_id"
    echo "fendermint_id: $fendermint_id"
    ;;

  ipc-cli)
    set +e
    docker_network=""
    docker network ls | grep $project_name > /dev/null
    [ $? == 0 ] && docker_network="--network $project_name"
    set -e
    docker run --name ipc-cli --rm -it $docker_network -v $(cd $workdir; pwd)/ipc:/fendermint/.ipc $fendermint_image "$@"
    ;;

  *)
    set_compose_files
    docker compose --env-file $workdir/generated/service-ips.env "$@"
    ;;
esac
