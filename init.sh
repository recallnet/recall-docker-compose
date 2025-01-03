#!/usr/bin/env bash

set -ex

source <(cat config/node.env | xargs -L 1 | sed -e 's/^/export &/')
docker compose up --abort-on-container-failure

