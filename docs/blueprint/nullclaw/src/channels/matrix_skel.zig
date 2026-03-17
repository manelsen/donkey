const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const url_percent = @import("../url_percent.zig");

const log = std.log.scoped(.matrix);

/// Matrix channel via Client-Server API.
///
/// - Inbound: long-poll /_matrix/client/v3/sync
/// - Outbound: PUT /_matrix/client/v3/rooms/{roomId}/send/m.room.message/{txnId}
/// - Typing: PUT /_matrix/client/v3/rooms/{roomId}/typing/{userId}
pub const MatrixChannel = struct {

fn stripTrailingSlashes(url: []const u8) []const u8

fn appendUrlEncoded(writer: anytype, text: []const u8) !void


test "MatrixChannel initFromConfig maps account and policy fields" {

    const ch = MatrixChannel.initFromConfig(std.testing.allocator, cfg);

test "MatrixChannel buildTypingUrl encodes room and user ids" {

    var buf: [512]u8 = undefined;
    const url = try ch.buildTypingUrl(&buf, "!room:example", "@bot:example");

test "MatrixChannel sendTypingIndicator is no-op in tests" {

test "MatrixChannel startTyping and stopTyping are safe in tests" {

test "MatrixChannel parseSyncResponse extracts messages and next_batch" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);


test "MatrixChannel parseSyncResponse marks m.direct rooms as direct chats" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);


test "MatrixChannel parseSyncResponse allowlist and policy semantics" {
    const allocator = std.testing.allocator;


    const blocked = try ch_allow.parseSyncResponse(allocator, payload_blocked);


    const open_msgs = try ch_open.parseSyncResponse(allocator, payload_open);

test "MatrixChannel parseSyncResponse drops all when group_policy is disabled" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);

test "MatrixChannel parseSyncResponse skips self and malformed payload safely" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);

    const malformed = try ch.parseSyncResponse(allocator, "{

test "MatrixChannel parseSyncResponse group_allow_from overrides fallback allow_from" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);


test "MatrixChannel parseSyncResponse with empty room_id accepts multiple rooms" {
    const allocator = std.testing.allocator;



    const msgs = try ch.parseSyncResponse(allocator, payload);


    var saw_a = false;
    var saw_b = false;
