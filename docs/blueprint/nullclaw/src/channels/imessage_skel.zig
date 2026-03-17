const std = @import("std");
const builtin = @import("builtin");
const build_options = @import("build_options");
const root = @import("root.zig");
const bus_mod = @import("../bus.zig");
const config_types = @import("../config_types.zig");
const platform = @import("../platform.zig");
const thread_stacks = @import("../thread_stacks.zig");

const log = std.log.scoped(.imessage);

const sqlite_mod = if (build_options.enable_sqlite) @import("../memory/engines/sqlite.zig") else @import("../memory/engines/sqlite_disabled.zig");
const c = sqlite_mod.c;
const SQLITE_STATIC = sqlite_mod.SQLITE_STATIC;
const CHAT_TARGET_PREFIX = "chat:";
const POLL_BATCH_LIMIT: c_int = 20;

/// iMessage channel — macOS Messages.app bridge.
///
/// Inbound:
///   Polls ~/Library/Messages/chat.db for new messages and publishes them to the event bus.
/// Outbound:
///   Sends via AppleScript (`osascript`) either to participant (phone/email) or chat GUID.
pub const IMessageChannel = struct {


fn parseSendTarget(target: []const u8) !ParsedSendTarget

// ════════════════════════════════════════════════════════════════════════════
// AppleScript Escaping (CWE-78 Prevention)
// ════════════════════════════════════════════════════════════════════════════

/// Escape a string for safe interpolation into AppleScript.
/// Prevents injection by escaping backslashes, quotes, and newlines.
pub fn escapeAppleScript(allocator: std.mem.Allocator, s: []const u8) ![]u8

/// Validate participant target (phone/email).
pub fn isValidTarget(target: []const u8) bool

/// Validate a chat GUID target used as `chat:<guid>`.
pub fn isValidChatGuid(chat_guid: []const u8) bool

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

fn createTestDb(allocator: std.mem.Allocator) ![]u8

    var db: ?*c.sqlite3 = null;
    const path_z = try allocator.dupeZ(u8, db_path);

    // handle row
        var stmt: ?*c.sqlite3_stmt = null;

    // message row
        var stmt: ?*c.sqlite3_stmt = null;

        var stmt_chat: ?*c.sqlite3_stmt = null;

        var stmt_join: ?*c.sqlite3_stmt = null;

test "escape applescript double quotes" {
    const allocator = std.testing.allocator;
    const result = try escapeAppleScript(allocator, "hello \"world\"");

test "escape applescript backslashes" {
    const allocator = std.testing.allocator;
    const result = try escapeAppleScript(allocator, "path\\to\\file");

test "escape applescript newlines" {
    const allocator = std.testing.allocator;
    const result = try escapeAppleScript(allocator, "line1\nline2");

test "escape applescript injection attempt" {
    const allocator = std.testing.allocator;
    const result = try escapeAppleScript(allocator, "\" & do shell script \"id\" & \"");

test "valid target phone" {

test "valid target email" {

test "invalid target injection attempt" {

test "valid chat guid target" {

test "imessage creates with contacts" {
    const contacts = [_][]const u8{

test "imessage contact allowlist is case insensitive" {
    const contacts = [_][]const u8{

test "pollMessagesFromDb parses direct message" {
    const allocator = std.testing.allocator;
    const db_path = try createTestDb(allocator);


    var ch = IMessageChannel.init(allocator, &.{

test "pollMessagesFromDb parses group chat and uses chat reply target" {
    const allocator = std.testing.allocator;
    const db_path = try createTestDb(allocator);


    var ch = IMessageChannel.init(allocator, &.{

test "pollMessages initializes cursor and skips backlog on first call" {
    const allocator = std.testing.allocator;
    const db_path = try createTestDb(allocator);


    var ch = IMessageChannel.init(allocator, &.{

test "imessage senderAllowedForContext respects group policy and fallback allowlists" {
    const allocator = std.testing.allocator;

    var ch = IMessageChannel.init(allocator, &.{

test "imessage publishInboundMessage emits group session key and metadata" {
    const allocator = std.testing.allocator;
    var eb = bus_mod.Bus.init();

    var ch = IMessageChannel.init(allocator, &.{

test "imessage publishInboundMessage emits direct session key and dm metadata" {
    const allocator = std.testing.allocator;
    var eb = bus_mod.Bus.init();

    var ch = IMessageChannel.init(allocator, &.{
