//! CLI entry point — single-message and interactive REPL modes.
//!
//! Extracted from agent/root.zig. Contains `run()` (the main entry point
//! for `nullclaw agent`) and the streaming stdout callback.

const std = @import("std");
const log = std.log.scoped(.agent);
const Config = @import("../config.zig").Config;
const providers = @import("../providers/root.zig");
const Provider = providers.Provider;
const http_util = @import("../http_util.zig");
const tools_mod = @import("../tools/root.zig");
const Tool = tools_mod.Tool;
const memory_mod = @import("../memory/root.zig");
const Memory = memory_mod.Memory;
const bootstrap_mod = @import("../bootstrap/root.zig");
const observability = @import("../observability.zig");
const Observer = observability.Observer;
const ObserverEvent = observability.ObserverEvent;
const subagent_mod = @import("../subagent.zig");
const subagent_runner = @import("../subagent_runner.zig");
const cli_mod = @import("../channels/cli.zig");
const security = @import("../security/policy.zig");
const codex_support = @import("../codex_support.zig");
const onboard = @import("../onboard.zig");
const streaming = @import("../streaming.zig");
const verbose = @import("../verbose.zig");

const Agent = @import("root.zig").Agent;

const CliStreamCtx = struct {

fn shouldPrintTurnResponse(supports_streaming: bool, emitted_text: bool) bool

fn cliStreamSinkCallback(_: *anyopaque, event: streaming.Event) void

/// Streaming callback that forwards provider chunks into unified stream sink events.
fn cliStreamCallback(ctx_ptr: *anyopaque, chunk: providers.StreamChunk) void

fn hasOpenAiCodexCredential(allocator: std.mem.Allocator) bool

fn shouldPrintOpenAiCodexHint(default_provider: []const u8, has_codex_credential: bool) bool


fn providerFailureLooksQuotaConstrained(detail: []const u8) bool

fn writeRateLimitHint(w: *std.Io.Writer, default_provider: []const u8) !void

    const detail = providers.snapshotLastApiErrorDetail(allocator) catch null;

    const detail = providers.snapshotLastApiErrorDetail(allocator) catch null;

const ParsedAgentArgs = struct {


fn parseAgentArgs(args: []const []const u8) AgentArgParseResult

/// Run the agent in single-message or interactive REPL mode.
/// This is the main entry point called by `nullclaw agent`.
pub fn run(allocator: std.mem.Allocator, args: []const [:0]const u8) !void

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

fn noopSinkEvent(_: *anyopaque, _: streaming.Event) void