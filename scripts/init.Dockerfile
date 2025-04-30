ARG cometbft_image="cometbft/cometbft:v0.37.x"
ARG fendermint_image="textile/fendermint:latest"

FROM $cometbft_image AS cometbft

FROM $fendermint_image

ARG NU_VERSION=0.103.0

# install nushell
RUN set -ex; \
  arch=$(uname -m | sed -e s/arm64/aarch64/); \
  curl -Lo nu.tgz https://github.com/nushell/nushell/releases/download/${NU_VERSION}/nu-${NU_VERSION}-${arch}-unknown-linux-gnu.tar.gz; \
  tar xf nu.tgz; \
  mv nu-*/nu /usr/local/bin/;\
  rm -rf nu-* nu.tgz

# install cometbft
COPY --from=cometbft /usr/bin/cometbft /usr/local/bin/

# install foundry tools
RUN set -x; \
  arch=$(uname -m | sed -e s/aarch64/arm64/ -e s/x86_64/amd64/); \
  apt update && apt install -y curl && \
  curl -Lo /tmp/tt.tgz https://github.com/foundry-rs/foundry/releases/download/stable/foundry_stable_linux_${arch}.tar.gz && \
  tar xvf /tmp/tt.tgz -C /usr/bin && \
  rm /tmp/tt.tgz

ENTRYPOINT [ "nu" ]
