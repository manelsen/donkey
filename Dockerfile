# Donkey Dockerfile - Multi-stage build for Nim
FROM nimlang/nim:2.2.8-alpine-regular AS builder

RUN apk add --no-cache openssl-dev postgresql-dev

WORKDIR /app
COPY . .
RUN nimble build -y -d:release -d:ssl -d:withPostgres

# Production image
FROM alpine:latest
RUN apk add --no-cache libssl3 libcrypto3 libpq docker-cli timeout python3

WORKDIR /app
COPY --from=builder /app/donkey /app/donkey
COPY --from=builder /app/deploy /app/deploy

# Expose metrics port
EXPOSE 8080

ENTRYPOINT ["/app/donkey"]
CMD ["start"]
