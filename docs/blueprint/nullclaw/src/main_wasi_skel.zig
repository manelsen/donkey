const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const fs_compat = @import("fs_compat.zig");

const MAX_READ_BYTES: usize = 1024 * 1024;
const MAX_SEARCH_MATCHES: usize = 5;

const DEFAULT_WORKSPACE = ".";





const ParsedWorkspaceArgs = struct {

const MemoryMatch = struct {

const Command = enum {

fn parse_command(arg: []const u8) ?Command

fn print_out(comptime fmt: []const u8, args: anytype) !void

fn print_err(comptime fmt: []const u8, args: anytype) !void

fn print_usage() !void

fn parse_workspace_args(allocator: std.mem.Allocator, args: []const []const u8) !ParsedWorkspaceArgs

fn join_path(allocator: std.mem.Allocator, a: []const u8, b: []const u8) ![]u8

fn ensure_parent_dir(path: []const u8) !void

fn file_exists(path: []const u8) bool

fn read_file_if_present(allocator: std.mem.Allocator, path: []const u8) !?[]u8

fn write_file_truncate(path: []const u8, content: []const u8) !void

fn write_if_missing(path: []const u8, content: []const u8) !bool

fn append_line(path: []const u8, line: []const u8, allocator: std.mem.Allocator) !void

fn scaffold_workspace(allocator: std.mem.Allocator, workspace: []const u8) !usize

fn memory_line_payload(raw_line: []const u8) ?[]const u8

fn count_memory_entries(text: []const u8) usize

fn contains_case_insensitive(haystack: []const u8, needle: []const u8) bool

    var query_tokens: std.ArrayList([]const u8) = .empty;
    var token_it = std.mem.tokenizeAny(u8, query, " \t\r\n");
    const tokens = try query_tokens.toOwnedSlice(allocator);

    var matches: std.ArrayList(MemoryMatch) = .empty;
    var line_it = std.mem.splitScalar(u8, memory_text, '\n');
        const payload = memory_line_payload(raw_line) orelse continue;
        var score: u32 = 0;

        fn less_than(_: void, a: MemoryMatch, b: MemoryMatch) bool


fn to_single_line(allocator: std.mem.Allocator, text: []const u8) ![]u8

fn daily_log_path(allocator: std.mem.Allocator, workspace: []const u8) ![]u8

fn extract_agent_name(identity_text: ?[]const u8) []const u8

fn join_tokens(allocator: std.mem.Allocator, tokens: []const []const u8) ![]u8

fn run_onboard(allocator: std.mem.Allocator, args: []const []const u8) !void

fn run_status(allocator: std.mem.Allocator, args: []const []const u8) !void

fn run_identity(allocator: std.mem.Allocator, args: []const []const u8) !void

fn run_memory(allocator: std.mem.Allocator, args: []const []const u8) !void

fn run_agent(allocator: std.mem.Allocator, args: []const []const u8) !void

pub fn main() !void
