const std = @import("std");
const root = @import("root.zig");

pub const SentMessageMeta = struct {

pub const ForumTopicMeta = struct {

pub const BotIdentity = struct {

pub const Client = struct {

pub fn appendReplyTo(body: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, reply_to: ?i64) !void

pub fn appendMessageThreadId(body: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, message_thread_id: ?i64) !void

pub fn appendRawReplyMarkup(body: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, reply_markup_json: ?[]const u8) !void

pub fn responseHasTelegramError(resp: []const u8) bool

pub fn responseIsMessageTooLong(resp: []const u8) bool

pub fn parseRetryAfterSecs(allocator: std.mem.Allocator, resp: []const u8) ?u32

pub fn parseSentMessageMeta(allocator: std.mem.Allocator, resp: []const u8) ?SentMessageMeta

pub fn parseForumTopicMeta(allocator: std.mem.Allocator, resp: []const u8) ?ForumTopicMeta

fn parseBotIdentity(allocator: std.mem.Allocator, resp: []const u8) ?BotIdentity

test "telegram api client builds method url" {
    var buf: [256]u8 = undefined;
    const url = try client.apiUrl(&buf, "getUpdates");

test "telegram api responseHasTelegramError matches error payloads" {

test "telegram api responseIsMessageTooLong matches telegram payloads" {

test "telegram api parseRetryAfterSecs extracts retry_after" {

test "telegram api parseSentMessageMeta extracts message id" {

test "telegram api parseForumTopicMeta extracts message thread id" {
