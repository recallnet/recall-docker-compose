# Hoku docker-compose

This repository contains scripts to deploy a hoku validator with docker-compose.

## Running Validator

### TL;DR
1. Copy `config/node-example.env` to `config/node.env` and edit `config/node.env`.
2. Run `./init.sh`
3. Run `./run.sh` or `./run.sh up -d` to run detached.

### How it works
Values in `config/node.env` overwrite values in `config/node-default.env`
