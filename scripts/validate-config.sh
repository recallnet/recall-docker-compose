#!/usr/bin/env bash

current_dir=$(dirname $0)
source $current_dir/read-config.sh

function fail {
  echo "❌"
  echo "ERROR: $1"
  exit 1
}

rpc_url="$parent_endpoint${parent_endpoint_token:+?token=$parent_endpoint_token}"
cast chain-id --rpc-url $rpc_url &> /dev/null
if [ $? != 0 ]; then
  fail "configured endpoint $parent_endpoint with provided 'parent_endpoint_token' is invalid"
fi

set -e
address=$(cast wallet address $node_private_key)
balance=$(cast balance --rpc-url $evm_rpc_url $address)
if [ $balance == 0 ]; then
  fail "no funds on subnet for the node address $address"
fi
