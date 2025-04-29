FROM alpine

ARG NU_VERSION=0.103.0

RUN apk add curl

RUN set -ex; \
  arch=$(uname -m | sed -e s/arm64/aarch64/); \
  curl -Lo nu.tgz https://github.com/nushell/nushell/releases/download/${NU_VERSION}/nu-${NU_VERSION}-${arch}-unknown-linux-musl.tar.gz; \
  tar xf nu.tgz; \
  mv nu-*/nu /bin/;\
  rm -rf nu-* nu.tgz

ENTRYPOINT [ "nu" ]
