# Donkey Dockerfile - SQLite-first Alpine runtime.
# Nim is built from the official source release: there is no nimlang/nim
# Alpine image for 2.4.2, and the prebuilt Linux tarball needs glibc.
FROM alpine:3.20 AS builder

ARG NIM_VERSION=2.4.2
ARG NIM_SHA256=b28bf4da1fce46dba9d16685c981b3d5e98de8db1b60d66f279b0bd2af2d8211

RUN apk add --no-cache build-base curl xz openssl-dev git
RUN curl -fsSL "https://nim-lang.org/download/nim-${NIM_VERSION}.tar.xz" -o /tmp/nim.tar.xz \
 && echo "${NIM_SHA256}  /tmp/nim.tar.xz" | sha256sum -c - \
 && mkdir -p /opt/nim && tar -xJf /tmp/nim.tar.xz -C /opt/nim --strip-components=1 \
 && cd /opt/nim && sh build.sh && bin/nim c -d:release koch && ./koch boot -d:release \
 && ./koch tools \
 && rm /tmp/nim.tar.xz
ENV PATH="/opt/nim/bin:/root/.nimble/bin:${PATH}"

WORKDIR /app
COPY . .
RUN nimble build -y -d:release -d:withSqlite

# Production image
FROM alpine:3.20

# Full-force runtime on a minimal Alpine base:
# - ca-certificates / openssl: HTTPS for providers and channels
# - docker-cli / timeout: Docker sandbox mode
# - python3: auxiliary tool/runtime expectations
# - git: native git tool + direct fallback shell flows
RUN apk add --no-cache \
  ca-certificates \
  openssl \
  docker-cli \
  docker-cli-compose \
  coreutils \
  python3 \
  git

WORKDIR /app
COPY --from=builder /app/donkey /app/donkey
COPY --from=builder /app/deploy /app/deploy
RUN chmod +x /app/deploy/entrypoint.sh

# Expose metrics port
EXPOSE 8080

ENTRYPOINT ["/app/deploy/entrypoint.sh"]
