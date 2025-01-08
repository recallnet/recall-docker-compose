#!/usr/bin/env bash

set -e

opts="-f ./docker-compose.init.yml --env-file ./config/node-default.env --env-file ./config/node.env"
trap "docker compose $opts down" EXIT

docker compose $opts up --abort-on-container-failure

