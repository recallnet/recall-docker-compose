#!/usr/bin/env bash

set -e

mkdir /fendermint/.ipc
echo "keystore_path = '/fendermint/.ipc'" > /fendermint/.ipc/config.toml
ipc-cli wallet new --wallet-type evm > /dev/null
cat /fendermint/.ipc/evm_keystore.json
