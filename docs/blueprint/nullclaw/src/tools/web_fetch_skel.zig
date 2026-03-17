//! Web Fetch Tool — fetch and extract content from web pages.
//!
//! Converts HTML to readable text/markdown. Removes scripts, styles,
//! and navigation. Preserves headings, links, and lists.

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const net_security = @import("../root.zig").net_security;
const http_util = @import("../http_util.zig");

const log = std.log.scoped(.web_fetch);

/// Default max chars for extracted content.
const DEFAULT_MAX_CHARS: usize = 50_000;

/// Web fetch tool — fetches URLs and extracts readable content.
pub const WebFetchTool = struct {

fn parseMaxChars(args: JsonObjectMap) usize

fn parseMaxCharsWithDefault(args: JsonObjectMap, default: usize) usize

fn shouldUseCurlResolve(host: []const u8) bool

    const host_for_resolve = net_security.stripHostBrackets(host);


/// Convert HTML to readable text with basic markdown formatting.
pub fn htmlToText(allocator: std.mem.Allocator, html: []const u8) ![]u8

fn appendNewline(buf: *std.ArrayList(u8), allocator: std.mem.Allocator, consecutive: *u32) !void

fn tagName(content: []const u8) []const u8

fn eqlTag(a: []const u8, b: []const u8) bool

fn isBlockTag(tag: []const u8) bool

fn extractHref(tag_content: []const u8) ?[]const u8

const ClosingTagPos = struct { start: usize, end: usize };