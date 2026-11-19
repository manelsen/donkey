## HTTP gateway — embedded HTTP/1.1 server for browser/UI clients.
##
## Runs on a dedicated OS thread (same pattern as WeChat/QQ webhook servers).
## Port: DONKEY_HTTP_PORT env var, default 8080.
##
## Endpoints:
##   GET /             → 200 OK, plain-text info (public health probe)
##   GET /health       → 200 OK, plain-text "ok" (public health probe)
##   GET /api/status   → DaemonStatus JSON
##   GET /api/logs     → recent log entries JSON (?n=N, default 50)
##   GET /api/events    → SSE stream of log events (long-lived connection)
##   POST /api/chat     → receive inbound message from web UI (bidirectional SSE)
##
## CORS: Access-Control-Allow-Origin: * for local browser access.
##
## Auth: `GET /`, `/health` and `/dashboard` are public (liveness probes plus a
## data-free shell that asks for the Bearer token and keeps it in
## sessionStorage). Every `/api/*` route, including `/api/sessions` and
## `/api/providers`, requires `Authorization: Bearer <DONKEY_HTTP_TOKEN>` even on
## loopback and even for `OPTIONS`: there is no unauthenticated mode for the
## data routes, so a gateway started without a token answers `401` there and the
## shell is the only thing left open. The `/v1/*` agent routes keep their
## historical local-only behaviour for an empty token; the agent itself already
## refuses to run without one.
##
## The token authenticates the client against the instance, never a user: the
## `user` field of a request is caller-asserted, so any token holder may act as
## any `api:<name>`. Per-user authentication is an explicit PRD non-goal and is
## pinned by `tests/app/t_http_gateway.nim` so the limitation stays deliberate.
##
## The implementation is split into `gateway_types` (shared state and hooks),
## `gateway_auth` (policy), `dashboard_assets` (the HTML shell),
## `gateway_routes` (pure parsing/builders) and `gateway_server` (sockets and
## pool lifecycle). This module is their facade so existing importers keep
## working unchanged.

import ./gateway_types
import ./gateway_auth
import ./dashboard_assets
import ./gateway_routes
import ./gateway_server

export gateway_types
export gateway_auth
export dashboard_assets
export gateway_routes
export gateway_server
