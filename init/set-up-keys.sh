set -eu

cometbft_dir=/workdir/cometbft
fendermint_dir=/workdir/fendermint
relayer_dir=/workdir/relayer
fendermint_keys_dir=$fendermint_dir/keys

# === Fendermint
mkdir -p $fendermint_keys_dir

eth_pk=/tmp/key
echo $validator_private_key > $eth_pk
trap "rm -f $eth_pk" EXIT

# Validator's key
fendermint key from-eth -s $eth_pk -n validator -o $fendermint_dir/keys

# Network key
fendermint key gen --name network --out-dir $fendermint_dir/keys


# === CometBFT
fendermint key into-tendermint -s $fendermint_keys_dir/validator.sk -o $cometbft_dir/config/priv_validator_key.json

# === Generated
mkdir -p /workdir/generated/ipc
cfg=/workdir/generated/ipc/config.toml
echo "keystore_path = '/workdir/generated/ipc'" > $cfg
ipc-cli --config-path $cfg wallet import --wallet-type evm --private-key $validator_private_key


# === Relayer
if [ $enable_relayer == "true" ]; then
  mkdir -p $relayer_dir/ipc
  cfg=$relayer_dir/ipc/config.toml
  echo "keystore_path = '$relayer_dir/ipc'" > $cfg
  ipc-cli --config-path $cfg wallet import --wallet-type evm --private-key $relayer_private_key
fi
