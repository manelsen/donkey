const std = @import("std");
const builtin = @import("builtin");
const root = @import("../root.zig");
const http_util = @import("../../http_util.zig");
const search_base_url = @import("../../search_base_url.zig");
const url_percent = @import("../../url_percent.zig");

const log = std.log.scoped(.web_search);

pub const ToolResult = root.ToolResult;


pub const ResultEntry = struct {

pub fn logRequestError(provider: []const u8, query: []const u8, err: anytype) void





pub fn timeoutToString(allocator: std.mem.Allocator, timeout_secs: u64) ![]u8



pub fn urlEncode(allocator: std.mem.Allocator, input: []const u8) ![]u8

pub fn urlEncodePath(allocator: std.mem.Allocator, input: []const u8) ![]u8

fn hexDigit(v: u8) u8

pub fn formatJinaPlainText(allocator: std.mem.Allocator, text: []const u8, query: []const u8) !ToolResult

pub fn formatResultEntries(allocator: std.mem.Allocator, query: []const u8, entries: []const ResultEntry) !ToolResult

    var buf: std.ArrayList(u8) = .empty;


    var out_idx: usize = 0;

        const title = extractString(obj, "title") orelse "(no title)";
        const url = extractString(obj, "url") orelse "(no url)";




pub fn extractString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8

pub fn duckduckgoTitleFromText(text: []const u8) []const u8
