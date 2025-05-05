#!/usr/bin/env bash

set -eu

export IPC_CLI_CONFIG_PATH=/relayer/ipc/config.toml

ipc-cli checkpoint relayer \
  --subnet $subnet_id \
  --submitter $relayer_address \
  --checkpoint-interval-sec 600 \
  --max-parallelism 1 \
  --metrics-address 0.0.0.0:9184
