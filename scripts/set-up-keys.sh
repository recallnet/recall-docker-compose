set -eux

eth_pk=/tmp/key
echo $validator_private_key > $eth_pk

mkdir /tmp/out
fendermint key from-eth -s $eth_pk -n validator -o /tmp/out
fendermint key into-tendermint -s /tmp/out/validator.sk -o /workdir/cometbft/config/priv_validator_key.json

rm -r $eth_pk /tmp/out
