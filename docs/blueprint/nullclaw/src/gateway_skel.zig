//! HTTP Gateway — lightweight HTTP server for nullclaw.
//!
//! Mirrors ZeroClaw's axum-based gateway with:
//!   - Sliding-window rate limiting (per-IP)
//!   - Idempotency store (deduplicates webhook requests)
//!   - Body size limits (64KB max)
//!   - Request timeouts (30s)
//!   - Bearer token authentication (PairingGuard)
//!   - Endpoints: /health, /ready, /pair, /webhook, /a2a, /.well-known/agent-card.json, /whatsapp, /telegram, /line, /lark, /qq, /max, /slack/events, /api/messages (Teams)
//!
//! Uses std.http.Server (built-in, no external deps).

const std = @import("std");
const build_options = @import("build_options");
const daemon = @import("daemon.zig");
const health = @import("health.zig");
const Config = @import("config.zig").Config;
const config_types = @import("config_types.zig");
const session_mod = @import("session.zig");
const providers = @import("providers/root.zig");
const http_util = @import("http_util.zig");
const tools_mod = @import("tools/root.zig");
const memory_mod = @import("memory/root.zig");
const bootstrap_mod = @import("bootstrap/root.zig");
const subagent_mod = @import("subagent.zig");
const subagent_runner = @import("subagent_runner.zig");
const observability = @import("observability.zig");
const agent_routing = @import("agent_routing.zig");
const security = @import("security/policy.zig");
const PairingGuard = @import("security/pairing.zig").PairingGuard;
const constantTimeEq = @import("security/pairing.zig").constantTimeEq;
const channels = @import("channels/root.zig");
const bus_mod = @import("bus.zig");
const a2a = @import("a2a.zig");
const thread_stacks = @import("thread_stacks.zig");

/// Maximum request body size (64KB) — prevents memory exhaustion.
pub const MAX_BODY_SIZE: usize = 65_536;
const MAX_HEADER_SIZE: usize = 8_192;
const MAX_HTTP_REQUEST_SIZE: usize = MAX_HEADER_SIZE + MAX_BODY_SIZE;

/// Request timeout (30s) — prevents slow-loris attacks.
pub const REQUEST_TIMEOUT_SECS: u64 = 30;
const ACCEPT_POLL_INTERVAL_MS: u64 = 100;

/// Sliding window for rate limiting (60s).
pub const RATE_LIMIT_WINDOW_SECS: u64 = 60;

/// How often the rate limiter sweeps stale IP entries (5 min).
const RATE_LIMITER_SWEEP_INTERVAL_SECS: u64 = 300;
const MAX_OBSERVED_TOOL_EVENTS: usize = 512;

const GatewayObservedToolEventKind = enum { start, result };
/// Thread-safe observer that records tool call events within the gateway.
/// Used to enrich webhook responses with tool execution summaries.