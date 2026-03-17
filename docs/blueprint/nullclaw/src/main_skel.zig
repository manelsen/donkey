const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const yc = @import("nullclaw");
const control_plane = yc.control_plane;

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn

const log = std.log.scoped(.main);

const Command = enum {

const SERVICE_SUBCOMMANDS = "install|start|stop|restart|status|uninstall";
const CRON_SUBCOMMANDS = "list|add|add-agent|once|once-agent|remove|pause|resume|run|update|runs";
const CHANNEL_SUBCOMMANDS = "list|start|status|add|remove";
const SKILLS_SUBCOMMANDS = "list|install|remove|info";
const HARDWARE_SUBCOMMANDS = "scan|flash|monitor";
const MEMORY_SUBCOMMANDS = "stats|count|reindex|search|get|list|drain-outbox|forget";
const HISTORY_SUBCOMMANDS = "list|show";
const WORKSPACE_SUBCOMMANDS = "edit|reset-md";
const MODELS_SUBCOMMANDS = "list|info|benchmark|refresh";
const AUTH_SUBCOMMANDS = "login|status|logout";


fn parseCommand(arg: []const u8) ?Command


fn configureWindowsConsoleUtf8() void

pub fn main() !void

fn printVersion() void

const GatewayDaemonOverrideError = error{

fn printMemoryRuntimeInitFailure(allocator: std.mem.Allocator, backend: []const u8) void

fn printRetrievalScoreLine(c: yc.memory.RetrievalCandidate) void

fn buildHistoryMemoryConfig(base: yc.config.config_types.MemoryConfig) yc.config.config_types.MemoryConfig

fn runMemory(allocator: std.mem.Allocator, sub_args: []const []const u8) !void


        const count = mem_rt.reindex(allocator);

        const drained = mem_rt.drainOutbox(allocator);

        const key = sub_args[1];

        const key = sub_args[1];
        const json_mode = hasJsonFlag(sub_args[2..]);
                var buf: [65536]u8 = undefined;
                var bw = std.fs.File.stdout().writer(&buf);
                const out = &bw.interface;
                var buf: [64]u8 = undefined;
                var bw = std.fs.File.stdout().writer(&buf);
                const out = &bw.interface;

        var limit: usize = 20;
        var category_opt: ?yc.memory.MemoryCategory = null;
        var json_mode = false;

        var i: usize = 1;


        const shown = @min(limit, entries.len);

            var buf: [65536]u8 = undefined;
            var bw = std.fs.File.stdout().writer(&buf);
            const out = &bw.interface;
                const preview_len = @min(@as(usize, 120), e.content.len);
                const preview = e.content[0..preview_len];

        const query = sub_args[1];
        var limit: usize = 6;
        var json_mode = false;

        var i: usize = 2;


            var buf: [65536]u8 = undefined;
            var bw = std.fs.File.stdout().writer(&buf);
            const out = &bw.interface;
                const preview_len = @min(@as(usize, 140), rc.snippet.len);
                const preview = rc.snippet[0..preview_len];


// ── History ──────────────────────────────────────────────────────

fn runHistory(allocator: std.mem.Allocator, sub_args: []const []const u8) !void

fn writeHistoryListJson(sessions: []const yc.memory.SessionInfo, total: u64, limit: usize, offset: usize) void