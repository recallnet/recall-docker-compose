ARG fendermint_image
FROM $fendermint_image

RUN apt update && apt install -y gettext-base curl jq bash

# Install foundry
RUN set -ex; \
  arch=$(uname -m | sed -e s/aarch64/arm64/ -e s/x86_64/amd64/); \
  curl -Lo /tmp/tt.tgz https://github.com/foundry-rs/foundry/releases/download/stable/foundry_stable_linux_${arch}.tar.gz && \
  tar xvf /tmp/tt.tgz -C /bin && \
  rm /tmp/tt.tgz

ENTRYPOINT [ "bash" ]
