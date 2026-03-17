//! HTTP client for the Max messenger Bot API (platform-api.max.ru).
//!
//! Provides typed wrappers for the Max Bot REST endpoints:
//!   GET /me, POST /messages, PUT /messages, DELETE /messages,
//!   POST /answers, GET /updates, POST /subscriptions, DELETE /subscriptions,
//!   POST /chats/{chatId}/actions, POST /uploads.

const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const url_percent = @import("../url_percent.zig");

const log = std.log.scoped(.max_api);

// ════════════════════════════════════════════════════════════════════════════
// Constants
// ════════════════════════════════════════════════════════════════════════════

pub const BASE_URL = "https://platform-api.max.ru";
pub const MAX_MESSAGE_LEN: usize = 4000;

// Update types requested via long-polling.
const UPDATE_TYPES = "message_created,message_callback,message_edited,message_removed,bot_added,bot_removed,bot_started,bot_stopped";

// ════════════════════════════════════════════════════════════════════════════
// Types
// ════════════════════════════════════════════════════════════════════════════

pub const BotInfo = struct {

pub const SentMessageMeta = struct {

pub const UploadDescriptor = struct {

pub const InlineKeyboardButton = struct {

// ════════════════════════════════════════════════════════════════════════════
// Client
// ════════════════════════════════════════════════════════════════════════════

pub const Client = struct {
    // ── URL builder ─────────────────────────────────────────────────────
    /// Build a full API URL into `buf`. Returns a slice of `buf`.
    ///   buildUrl(buf, "/me", null)         → "https://platform-api.max.ru/me"
    ///   buildUrl(buf, "/messages", "chat_id=123") → ".../messages?chat_id=123"

// ════════════════════════════════════════════════════════════════════════════
// Internal: DELETE via curl subprocess
// ════════════════════════════════════════════════════════════════════════════

fn curlDelete(allocator: std.mem.Allocator, url: []const u8, auth_header: []const u8, proxy: ?[]const u8) !void

    var file_arg_buf: [1024]u8 = undefined;
    var file_fbs = std.io.fixedBufferStream(&file_arg_buf);
    const file_arg = file_fbs.getWritten();

    var argv_buf: [18][]const u8 = undefined;
    var argc: usize = 0;



    var child = std.process.Child.init(argv_buf[0..argc], allocator);

    const stdout = child.stdout.?.readToEndAlloc(allocator, 1024 * 1024) catch return error.CurlReadError;

// ════════════════════════════════════════════════════════════════════════════
// JSON body builders (free functions)
// ════════════════════════════════════════════════════════════════════════════

/// Build a JSON body for a plain text message.
///   { "text": "...", "format": "..." }
/// `format` is optional (e.g. "markdown", "html"); omitted when null.
pub fn buildTextMessageBody(allocator: std.mem.Allocator, text: []const u8, format: ?[]const u8) ![]u8

    var buf: std.ArrayListUnmanaged(u8) = .empty;



/// Build a JSON body for a text message with an inline keyboard.
///   { "text": "...", "format": "...", "attachments": [{ "type": "inline_keyboard", "payload": { "buttons": [...] } }] }
pub fn buildTextWithKeyboardBody(allocator: std.mem.Allocator, text: []const u8, keyboard_json: []const u8, format: ?[]const u8) ![]u8

/// Build an inline keyboard JSON payload from a slice of choice labels.
///   { "buttons": [[{"type":"callback","text":"A","payload":"A"}], ...] }
/// Each choice becomes a single-button row.
pub fn buildInlineKeyboardJson(allocator: std.mem.Allocator, choices: []const []const u8) ![]u8

    var buf: std.ArrayListUnmanaged(u8) = .empty;



// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "buildUrl without query" {
    var buf: [256]u8 = undefined;
    const url = try Client.buildUrl(&buf, "/me", null);

test "buildUrl with query params" {
    var buf: [256]u8 = undefined;
    const url = try Client.buildUrl(&buf, "/messages", "chat_id=123");

test "buildUrl with compound query" {
    var buf: [512]u8 = undefined;
    const url = try Client.buildUrl(&buf, "/updates", "timeout=30&types=message_created&marker=abc");

test "authHeader uses raw token format required by Max" {
    var buf: [128]u8 = undefined;
    const header = try client.authHeader(&buf);

test "parseBotInfo with integer user_id" {
    const allocator = std.testing.allocator;
    const json = "{

test "parseBotInfo with string user_id" {
    const allocator = std.testing.allocator;
    const json = "{

test "parseBotInfo with invalid JSON returns null" {
    const allocator = std.testing.allocator;

test "parseBotInfo with empty object" {
    const allocator = std.testing.allocator;
    const info = Client.parseBotInfo(allocator, "{

test "parseSentMessageMid extracts mid" {
    const allocator = std.testing.allocator;
    const json = "{

test "parseSentMessageMid returns empty meta on missing mid" {
    const allocator = std.testing.allocator;
    const json = "{

test "parseSentMessageMid returns null on invalid JSON" {
    const allocator = std.testing.allocator;

test "parseUploadToken extracts token" {
    const allocator = std.testing.allocator;
    const json = "{

test "parseUploadDescriptor extracts url and token" {
    const allocator = std.testing.allocator;
    const desc = Client.parseUploadDescriptor(allocator, "{

test "parseUploadDescriptor allows upload url without token" {
    const allocator = std.testing.allocator;
    const desc = Client.parseUploadDescriptor(allocator, "{

test "parseUploadToken returns null on missing token" {
    const allocator = std.testing.allocator;

test "buildTextMessageBody without format" {
    const allocator = std.testing.allocator;
    const body = try buildTextMessageBody(allocator, "Hello, world!", null);

test "buildTextMessageBody with format" {
    const allocator = std.testing.allocator;
    const body = try buildTextMessageBody(allocator, "**bold**", "markdown");

test "buildTextMessageBody escapes special chars" {
    const allocator = std.testing.allocator;
    const body = try buildTextMessageBody(allocator, "line1\nline2", null);

test "buildTextMessageBodyClearingAttachments removes attachments" {
    const allocator = std.testing.allocator;
    const body = try buildTextMessageBodyClearingAttachments(allocator, "Pick one", "markdown");

test "buildInlineKeyboardJson with multiple choices" {
    const allocator = std.testing.allocator;
    const choices = [_][]const u8{

test "buildInlineKeyboardButtonsJson preserves custom payloads" {
    const allocator = std.testing.allocator;
    const json = try buildInlineKeyboardButtonsJson(allocator, &buttons);


test "getMe returns mock data in test mode" {
    const allocator = std.testing.allocator;
    const resp = try client.getMe(allocator);

test "sendMessage returns mock data in test mode" {
    const allocator = std.testing.allocator;
    const resp = try client.sendMessage(allocator, "123", "{

test "getMeOk returns true for valid mock response" {

test "MAX_MESSAGE_LEN is 4000" {

test "BASE_URL is correct" {
