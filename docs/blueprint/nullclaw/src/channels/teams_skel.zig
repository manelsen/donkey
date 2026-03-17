const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");
const bus_mod = @import("../bus.zig");

const log = std.log.scoped(.teams);

/// Microsoft Teams channel — Bot Framework REST API for outbound, webhook for inbound.
/// Uses Azure AD OAuth2 client credentials flow for authentication.
///
/// ## Teams Conversation ID Formats
///
/// Teams uses three different ID formats for the same conversation, depending on context:
///
/// 1. **Teams URL format** (`19:...@unq.gbl.spaces`) — visible in Teams deep-links and
///    the Teams client URL bar. NOT what Bot Framework uses.
///
/// 2. **Bot Framework `conversation.id`** (`a:1lFKq...`) — the ID in the Activity JSON
///    that Bot Framework sends to our webhook. This is the correct value for
///    `notification_channel_id` in config.json. Used for outbound API calls.
///
/// 3. **Session key format** (`29:...`) — sometimes seen in `from.id` or other fields.
///    NOT the conversation identifier.
///
/// When configuring `notification_channel_id`, use the Bot Framework format (type 2).
/// To discover it, send a message to the bot and check the `conversation.id` field
/// in the Activity JSON payload received at the `/api/messages` webhook.
pub const TeamsChannel = struct {
    // OAuth2 token cache
    // Config directory for conversation reference file persistence
    // Conversation reference for proactive messaging (serviceUrl + conversationId)
    // Placeholder activity ID cache: maps recipient target → activityId for pending placeholders.
    // Guarded by placeholder_mutex for thread safety (startTyping and vtableSend may run on different threads).

test "Teams startTyping and stopTyping are safe in tests" {
    // startTyping returns immediately when not running (running = false by default)

test "Teams stopTyping is idempotent" {

test "vtableSend strips nc_choices tags from message" {
    const msg = "Pick one:\n- Option A\n- Option B\n<nc_choices>{

test "placeholder cache stores and retrieves by target" {
    const target = "https://smba.trafficmanager.net/teams|19:abc@thread.v2";

    // cachePlaceholder dupes both target and activity_id internally

    // takePlaceholder returns the cached ID (caller owns) and frees the target key
    const taken = ch.takePlaceholder(target);

    // Second take returns null (already removed)

test "placeholder cache returns null for unknown target" {

test "placeholder cache replaces duplicate target" {
    const target = "https://smba.trafficmanager.net/teams|19:abc@thread.v2";


    const taken = ch.takePlaceholder(target);

    // Only one entry existed — second take is null

test "placeholder cache evicts oldest when full" {

    // Fill all slots
    var targets: [TeamsChannel.MAX_PLACEHOLDER_ENTRIES][32]u8 = undefined;
        var fbs = std.io.fixedBufferStream(&targets[i]);

    // Add one more — should evict first entry (target-0)

    // target-1 should still be there
    var fbs1: [32]u8 = undefined;
    var fbs1_stream = std.io.fixedBufferStream(&fbs1);
    const taken1 = ch.takePlaceholder(fbs1_stream.getWritten());

    // overflow should be there
    const taken_overflow = ch.takePlaceholder("target-overflow");

    // Clean up remaining entries
        var tgt_buf: [32]u8 = undefined;
        var tgt_fbs = std.io.fixedBufferStream(&tgt_buf);

test "vtableSend preserves message without nc_choices" {
    const msg = "Hello, how can I help?";
