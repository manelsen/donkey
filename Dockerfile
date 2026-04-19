# Donkey Dockerfile - SQLite-first Alpine runtime.
FROM nimlang/nim:alpine AS builder

RUN apk add --no-cache openssl-dev git

WORKDIR /app
RUN nimble install -y https://github.com/beef331/wasm3
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
RUN mkdir -p /root/.config/donkey /root/.donkey/paddocks && \
    cp /app/deploy/donkey.toml.hf /root/.config/donkey/donkey.toml

# Expose metrics port
EXPOSE 8080

ENTRYPOINT ["/app/donkey"]
CMD ["start", "--config", "/root/.config/donkey/donkey.toml"]
