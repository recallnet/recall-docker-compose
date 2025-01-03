#!/usr/bin/env bash

set -e

file=docker-compose.run.yml

docker compose -f $file --env-file ./config/node.env up $@

