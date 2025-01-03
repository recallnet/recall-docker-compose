#!/usr/bin/env bash

set -e

cmd=${@:-up}
opts="-f ./docker-compose.run.yml --env-file ./config/node.env"

docker compose $opts $cmd

