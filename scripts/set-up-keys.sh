set -eux

cometbft_dir=/workdir/cometbft
fendermint_dir=/workdir/fendermint
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

