set -a
cfg_dir=$(cd $(dirname $BASH_SOURCE)/../config; pwd)
source $cfg_dir/node-default.env
source $cfg_dir/node.env
source $cfg_dir/network-${network_name}.env
set +a
