const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const voice = @import("../voice.zig");
const platform = @import("../platform.zig");
const config_types = @import("../config_types.zig");
const control_plane = @import("../control_plane.zig");
const interaction_choices = @import("../interactions/choices.zig");
const streaming = @import("../streaming.zig");
const telegram_api = @import("telegram_api.zig");
const telegram_draft_presenter = @import("telegram_draft_presenter.zig");
const telegram_ingress = @import("telegram_ingress.zig");
const telegram_update_ingress = @import("telegram_update_ingress.zig");
const thread_stacks = @import("../thread_stacks.zig");
const Atomic = @import("../portable_atomic.zig").Atomic;

const log = std.log.scoped(.telegram);
const MEDIA_GROUP_FLUSH_SECS: u64 = 3;
const TEMP_MEDIA_SWEEP_INTERVAL_POLLS: u32 = 20;
const TEMP_MEDIA_TTL_SECS: i64 = 24 * 60 * 60;
const TOPIC_TARGET_SEPARATOR = "#topic:";

// ════════════════════════════════════════════════════════════════════════════
// Attachment Types
// ════════════════════════════════════════════════════════════════════════════

pub const AttachmentKind = enum {
    /// Return the Telegram API method name for this attachment kind.

pub const Attachment = struct {

pub const ParsedMessage = struct {

const OwnedOutboundPayload = struct {

const PendingInteractionOption = struct {

const PendingInteraction = struct {

const DraftState = telegram_draft_presenter.DraftState;

const ParsedTelegramTarget = struct {

pub const TaskReaction = enum {

fn parseTelegramTarget(target: []const u8) ParsedTelegramTarget

pub fn targetChatId(target: []const u8) []const u8

pub fn targetThreadId(target: []const u8) ?i64

fn dupTelegramTarget(allocator: std.mem.Allocator, chat_id: []const u8, message_thread_id: ?i64) ![]u8

fn countUtf8Codepoints(text: []const u8) !usize

/// Infer attachment kind from file extension.
pub fn inferAttachmentKindFromExtension(path: []const u8) AttachmentKind

fn eqlLower(a: []const u8, comptime b: []const u8) bool

fn isWindowsForbiddenFilenameChar(c: u8) bool

fn isWindowsReservedBaseName(name: []const u8) bool

/// Sanitize a filename component for cross-platform safety (especially Windows).
/// Replaces forbidden characters with `_`, trims trailing dot/space, and avoids
/// reserved DOS device names such as `CON` and `LPT1`.
fn sanitizeFilenameComponent(out: []u8, input: []const u8, limit: usize) []const u8

fn trimTrailingPathSeparators(path: []const u8) []const u8

fn pathSeparator(base: []const u8) []const u8

fn cloneChannelMessage(allocator: std.mem.Allocator, msg: root.ChannelMessage) !root.ChannelMessage

fn mediaGroupLatestSeen(group_id: []const u8, group_ids: []const ?[]const u8, received_at: []const u64) ?u64

fn nextPendingMediaDeadline(group_ids: []const ?[]const u8, received_at: []const u64) ?u64

fn sweepTempMediaFilesInDir(dir_path: []const u8, now_secs: i64, ttl_secs: i64) void

/// Parse attachment markers from LLM response text.
/// Scans for [IMAGE:...], [DOCUMENT:...], [VIDEO:...], [AUDIO:...], [VOICE:...] markers.
/// Returns extracted attachments and the remaining text with markers removed.
pub fn parseAttachmentMarkers(allocator: std.mem.Allocator, text: []const u8) !ParsedMessage

fn parseMarkerKind(kind_str: []const u8) ?AttachmentKind

fn to_root_attachment_kind(kind: AttachmentKind) root.Channel.OutboundAttachmentKind

fn from_root_attachment_kind(kind: root.Channel.OutboundAttachmentKind) AttachmentKind


    var options = try allocator.alloc(interaction_choices.ChoiceOption, choices.len);
    var built: usize = 0;




    var parsed_choices = try interaction_choices.parseAssistantChoices(allocator, text);

    const parsed = try parseAttachmentMarkers(allocator, parsed_choices.visible_text);

    const choices_enabled = allow_choices and parsed_choices.choices != null and parsed.attachments.len == 0 and media.len == 0;
    const attachments_len = parsed.attachments.len + media.len;
    var attachments = try allocator.alloc(root.Channel.OutboundAttachment, attachments_len);
    var built_attachments: usize = 0;


    var built_choices: usize = 0;



// ════════════════════════════════════════════════════════════════════════════
// Smart Message Splitting
// ════════════════════════════════════════════════════════════════════════════

/// Split a message into chunks respecting the max byte limit.
/// Prefers splitting at word boundaries (newline, then space) over mid-word.
pub fn smartSplitMessage(msg: []const u8, max_bytes: usize) SmartSplitIterator

pub const SmartSplitIterator = struct {

/// Telegram channel — uses the Bot API with long-polling (getUpdates).
/// Splits messages at 4096 chars (Telegram limit).
pub const TelegramChannel = struct {
    // Pending media group messages (buffered across poll cycles until group is complete)

// ════════════════════════════════════════════════════════════════════════════
// Markdown → Telegram HTML Conversion
// ════════════════════════════════════════════════════════════════════════════

/// Convert Markdown to Telegram-compatible HTML.
/// Handles: code blocks, inline code, bold, italic, strikethrough,
/// links, headers, bullet lists. Escapes HTML entities.
pub fn markdownToTelegramHtml(allocator: std.mem.Allocator, md: []const u8) ![]u8

fn findTripleBacktick(md: []const u8, from: usize) ?usize

/// Escape HTML entities for Telegram HTML parse_mode.
fn appendHtmlEscaped(buf: *std.ArrayListUnmanaged(u8), allocator: std.mem.Allocator, text: []const u8) !void

// ════════════════════════════════════════════════════════════════════════════
// Telegram Photo Download
// ════════════════════════════════════════════════════════════════════════════

// ════════════════════════════════════════════════════════════════════════════
// Media Group Merging
// ════════════════════════════════════════════════════════════════════════════

/// Merge messages that belong to the same `media_group_id` into a single message.
/// Handles interleaved groups (scans the full array, not just consecutive items)
/// and removes merged entries backward to avoid index-shifting bugs.
/// Memory-safe: only frees old content after new allocation succeeds.

    var i: usize = 0;

        // 1. Find all matching indices (supports interleaved messages)
        var match_indices: std.ArrayListUnmanaged(usize) = .empty;

        var j = i + 1;

            // 2. Build merged content
            var merged: std.ArrayListUnmanaged(u8) = .empty;
            var merge_ok = true;


            const new_content = if (merge_ok) (merged.toOwnedSlice(allocator) catch null) else null;

                // 3. Safely replace root content NOW that allocation succeeded

                // 4. Remove backwards to prevent index shifting
                var k: usize = match_indices.items.len;
                    const idx = match_indices.items[k];

                    const extra = messages.orderedRemove(idx);


/// Download a photo from Telegram by file_id. Returns the local temp file path (caller-owned).
fn downloadTelegramPhoto(allocator: std.mem.Allocator, bot_token: []const u8, file_id: []const u8, proxy: ?[]const u8) ?[]u8

/// Download any file from Telegram by file_id. Preserves the original filename when provided.
/// Returns the local temp file path (caller-owned).
fn downloadTelegramFile(allocator: std.mem.Allocator, bot_token: []const u8, file_id: []const u8, file_name: ?[]const u8, proxy: ?[]const u8) ?[]u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram api url" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

// ════════════════════════════════════════════════════════════════════════════
// Additional Telegram tests.
// ════════════════════════════════════════════════════════════════════════════

test "telegram api url sendDocument" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

test "telegram api url sendPhoto" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

test "telegram api url sendVideo" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

test "telegram api url sendAudio" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

test "telegram api url sendVoice" {
    const ch = TelegramChannel.init(std.testing.allocator, "123:ABC", &.{

test "telegram max message len constant" {

test "telegram build send body" {
    var buf: [512]u8 = undefined;
    const body = try TelegramChannel.buildSendBody(&buf, "12345", "Hello!");

test "telegram init stores fields" {
    const users = [_][]const u8{

test "telegram init has null transcriber" {
    const ch = TelegramChannel.init(std.testing.allocator, "tok", &.{

// ════════════════════════════════════════════════════════════════════════════
// Attachment Marker Parsing Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram parseAttachmentMarkers extracts IMAGE marker" {
    const parsed = try parseAttachmentMarkers(std.testing.allocator, "Check this [IMAGE:/tmp/photo.png] out");


test "telegram parseAttachmentMarkers extracts multiple markers" {


test "telegram parseAttachmentMarkers returns remaining text without markers" {


test "telegram parseAttachmentMarkers keeps invalid markers in text" {


test "telegram parseAttachmentMarkers no markers returns full text" {


test "telegram parseAttachmentMarkers AUDIO and VOICE" {


test "telegram parseAttachmentMarkers case insensitive kind" {


test "telegram parseAttachmentMarkers empty text" {
    const parsed = try parseAttachmentMarkers(std.testing.allocator, "");


test "telegram parseAttachmentMarkers PHOTO alias" {


test "telegram parseAttachmentMarkers FILE alias" {


test "telegram buildOwnedOutboundPayloadFromLegacy lifts choices into structured payload" {


test "telegram buildOwnedOutboundPayloadFromLegacy suppresses choices when explicit media is present" {


test "telegram buildOwnedOutboundPayloadFromLegacy keeps choices disabled for plain send path" {


// ════════════════════════════════════════════════════════════════════════════
// inferAttachmentKindFromExtension Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram inferAttachmentKindFromExtension png is image" {

test "telegram inferAttachmentKindFromExtension jpg is image" {

test "telegram inferAttachmentKindFromExtension pdf is document" {

test "telegram inferAttachmentKindFromExtension mp4 is video" {

test "telegram inferAttachmentKindFromExtension mp3 is audio" {

test "telegram inferAttachmentKindFromExtension ogg is voice" {

test "telegram inferAttachmentKindFromExtension unknown is document" {

test "telegram inferAttachmentKindFromExtension no extension is document" {

test "telegram inferAttachmentKindFromExtension strips query string" {

test "telegram inferAttachmentKindFromExtension case insensitive" {

// ════════════════════════════════════════════════════════════════════════════
// Smart Split Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram smartSplitMessage splits at word boundary not mid-word" {
    const msg = "Hello World! Goodbye Friend";
    var it = smartSplitMessage(msg, 20);
    const chunk1 = it.next().?;
    // Should split at a space, not in the middle of "Goodbye"

    const chunk2 = it.next().?;

    // Verify all content preserved
    const total = chunk1.len + chunk2.len;

test "telegram smartSplitMessage splits at newline if available" {
    const msg = "First line\nSecond line that is longer than needed";
    var it = smartSplitMessage(msg, 20);
    const chunk1 = it.next().?;
    // Should prefer newline at position 10 (which is >= half of 20)

test "telegram smartSplitMessage short message no split" {
    var it = smartSplitMessage("short", 100);

test "telegram smartSplitMessage empty returns null" {
    var it = smartSplitMessage("", 100);

test "telegram smartSplitMessage no word boundary falls back to hard cut" {
    const msg = "abcdefghijklmnopqrstuvwxyz";
    var it = smartSplitMessage(msg, 10);
    const chunk1 = it.next().?;

test "telegram smartSplitMessage preserves total content" {
    const msg = "word " ** 100;
    var it = smartSplitMessage(msg, 50);
    var total: usize = 0;

test "telegram buildOutgoingTextChunks appends continuation only to non-last chunks" {
    const allocator = std.testing.allocator;
    const text = ("word " ** 900) ++ "tail";

    const chunks = try TelegramChannel.buildOutgoingTextChunks(allocator, text);


test "telegram buildOutgoingTextChunks reuses source slice when split is unnecessary" {
    const allocator = std.testing.allocator;
    const text = "Short reply";

    const chunks = try TelegramChannel.buildOutgoingTextChunks(allocator, text);


// ════════════════════════════════════════════════════════════════════════════
// Typing Indicator Test
// ════════════════════════════════════════════════════════════════════════════

test "telegram sendTypingIndicator does not crash with invalid token" {
    var ch = TelegramChannel.init(std.testing.allocator, "invalid:token", &.{

// ════════════════════════════════════════════════════════════════════════════
// Allowed Users Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram allow_from empty denies all" {
    const ch = TelegramChannel.init(std.testing.allocator, "tok", &.{

test "telegram allow_from non-empty filters correctly" {
    const users = [_][]const u8{

test "telegram allow_from wildcard allows all" {
    const users = [_][]const u8{

test "telegram allow_from case insensitive" {
    const users = [_][]const u8{

test "telegram allow_from strips @ prefix" {
    const users = [_][]const u8{

test "telegram isAnyIdentityAllowed matches username" {
    const users = [_][]const u8{

test "telegram isAnyIdentityAllowed matches numeric id" {
    const users = [_][]const u8{

test "telegram isAnyIdentityAllowed denies when none match" {
    const users = [_][]const u8{

test "telegram isAnyIdentityAllowed wildcard allows all" {
    const users = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// AttachmentKind Method Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram AttachmentKind apiMethod returns correct methods" {

test "telegram AttachmentKind formField returns correct fields" {

// ════════════════════════════════════════════════════════════════════════════
// Markdown → HTML Conversion Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram markdownToTelegramHtml bold" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "This is **bold** text");

test "telegram markdownToTelegramHtml italic" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "This is _italic_ text");

test "telegram markdownToTelegramHtml inline code" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "Use `code` here");

test "telegram markdownToTelegramHtml code block" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "```\nhello\n```");

test "telegram markdownToTelegramHtml code block with language" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "```python\nprint('hi')\n```");

test "telegram markdownToTelegramHtml strikethrough" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "This is ~~deleted~~ text");

test "telegram markdownToTelegramHtml link" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "Click [here](https://example.com)");

test "telegram markdownToTelegramHtml header" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "# Title\n## Subtitle");

test "telegram markdownToTelegramHtml bullet list" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "- Item 1\n- Item 2");

test "telegram markdownToTelegramHtml escapes HTML entities" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "A < B & C > D");

test "telegram markdownToTelegramHtml plain text passthrough" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "Just plain text.");

test "telegram markdownToTelegramHtml empty" {
    const html = try markdownToTelegramHtml(std.testing.allocator, "");

test "telegram typing handles start empty" {
    var ch = TelegramChannel.init(std.testing.allocator, "tok", &.{

test "telegram startTyping stores handle and stopTyping clears it" {
    var ch = TelegramChannel.init(std.testing.allocator, "tok", &.{

test "telegram stopTyping is idempotent" {
    var ch = TelegramChannel.init(std.testing.allocator, "tok", &.{

// ════════════════════════════════════════════════════════════════════════════
// Multipart URL Detection Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram sendMediaMultipart URL detection for http" {
    // Verify URL detection logic (same logic used in sendMediaMultipart)
    const url = "https://example.com/photo.jpg";

test "telegram sendMediaMultipart URL detection for local file" {
    const path = "/tmp/photo.png";

test "telegram sendMediaMultipart data URI treated as local file" {
    // data: URIs are NOT treated as URLs in sendMediaMultipart (would overflow the
    // 1024-byte buffer and curl can't upload them). They are passed as local file @paths.
    const data_uri = "data:image/png;base64,iVBOR";

test "telegram sanitizeFilenameComponent replaces Windows-invalid chars" {
    var buf: [64]u8 = undefined;
    const sanitized = sanitizeFilenameComponent(&buf, "report:Q1*?.txt ", 64);

test "telegram sanitizeFilenameComponent avoids Windows reserved names" {
    var buf: [32]u8 = undefined;
    const con_name = sanitizeFilenameComponent(&buf, "CON", 32);

    var buf2: [32]u8 = undefined;
    const lpt_name = sanitizeFilenameComponent(&buf2, "LPT1.txt", 32);

test "telegram trimTrailingPathSeparators removes trailing slash from tmpdir" {
    const trimmed = trimTrailingPathSeparators("/var/folders/a/b/T/");

test "telegram trimTrailingPathSeparators keeps root slash" {
    const trimmed = trimTrailingPathSeparators("/");

test "telegram pathSeparator avoids duplicate slash" {

// ════════════════════════════════════════════════════════════════════════════
// Document Handling Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram parseAttachmentMarkers FILE with caption" {


test "telegram parseAttachmentMarkers multiple FILE markers" {


test "telegram parseAttachmentMarkers mixed FILE and IMAGE" {


test "telegram inferAttachmentKindFromExtension docx is document" {

test "telegram inferAttachmentKindFromExtension csv is document" {

test "telegram inferAttachmentKindFromExtension xlsx is document" {

test "telegram media group content merging" {
    // Simulate media group merging: two FILE markers from same group
    // should be concatenated with newline separator.
    const alloc = std.testing.allocator;
    const content1 = try alloc.dupe(u8, "[FILE:/tmp/a.docx]");
    const content2 = try alloc.dupe(u8, "[FILE:/tmp/b.csv] Вот файлы");

    // Merged content should contain both markers
    var merged: std.ArrayListUnmanaged(u8) = .empty;

    // Verify merged content parses correctly
    const parsed = try parseAttachmentMarkers(alloc, merged.items);


test "telegram media group content merging preserves caption" {
    const alloc = std.testing.allocator;
    // Simulate merged media group: images with caption on last one
    var merged: std.ArrayListUnmanaged(u8) = .empty;

    const parsed = try parseAttachmentMarkers(alloc, merged.items);


test "telegram parseAttachmentMarkers FILE with cyrillic filename" {


test "telegram buildAttachmentMetadataFallbackContent includes available metadata" {
    const alloc = std.testing.allocator;



test "telegram buildAttachmentMetadataFallbackContent omits optional fields" {
    const alloc = std.testing.allocator;



fn buildAttachmentMetadataFallbackContentAllocationTest(allocator: std.mem.Allocator) !void

test "telegram buildAttachmentMetadataFallbackContent frees partial allocations on out-of-memory" {

// ════════════════════════════════════════════════════════════════════════════
// mergeMediaGroups Tests
// ════════════════════════════════════════════════════════════════════════════

test "telegram mergeMediaGroups consecutive items" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var mgids: std.ArrayListUnmanaged(?[]const u8) = .empty;

    // Add two messages with same media_group_id



    // Should merge into 1 message

    // Clean up remaining message

test "telegram mergeMediaGroups interleaved items" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var mgids: std.ArrayListUnmanaged(?[]const u8) = .empty;

    // msg0: group_A

    // msg1: no group (standalone text)

    // msg2: group_A (interleaved)


    // Should merge group_A into 1 message, keep standalone text

    // First message: merged group_A content

    // Second message: standalone text

    // Clean up remaining messages

test "telegram mergeMediaGroups single item no merge" {
    const alloc = std.testing.allocator;
    var messages: std.ArrayListUnmanaged(root.ChannelMessage) = .empty;
    var mgids: std.ArrayListUnmanaged(?[]const u8) = .empty;

    // Single message with media_group_id (the group has only one item)


    // Should not merge — still 1 message

    // Clean up

test "telegram flushMaturedPendingMediaGroups flushes only mature groups" {
    const alloc = std.testing.allocator;
    var ch = TelegramChannel.init(alloc, "123:ABC", &.{

test "telegram persistableUpdateOffset waits until pending media flushes" {
    const alloc = std.testing.allocator;
    var ch = TelegramChannel.init(alloc, "123:ABC", &.{

test "telegram persistableUpdateOffset waits until pending text flushes" {
    const alloc = std.testing.allocator;
    var ch = TelegramChannel.init(alloc, "123:ABC", &.{

test "telegram flushMaturedPendingTextMessages waits for newest chain message" {
    const alloc = std.testing.allocator;
    var ch = TelegramChannel.init(alloc, "123:ABC", &.{

test "telegram processUpdate falls back to caption when text is absent" {
    const alloc = std.testing.allocator;
    var ch = TelegramChannel.init(alloc, "123:ABC", &.{

test "telegram nextPendingMediaDeadline returns earliest group deadline" {

    const deadline = nextPendingMediaDeadline(group_ids[0..], received_at[0..]);

test "telegram sweepTempMediaFilesInDir removes only stale nullclaw temp media files" {
    var tmp_dir = std.testing.tmpDir(.{

test "telegram resolveAttachmentPath expands tilde path" {
    const allocator = std.testing.allocator;
    const home = try platform.getHomeDir(allocator);

    const input = if (comptime builtin.os.tag == .windows) "~\\docs\\report.txt" else "~/docs/report.txt";
    const suffix = if (comptime builtin.os.tag == .windows) "docs\\report.txt" else "docs/report.txt";
    const expected = try std.fs.path.join(allocator, &.{

test "telegram resolveAttachmentPath keeps absolute local path unchanged" {
    const allocator = std.testing.allocator;
    const input = if (comptime builtin.os.tag == .windows) "C:\\tmp\\a.txt" else "/tmp/a.txt";

    const resolved = try TelegramChannel.resolveAttachmentPath(allocator, input);


fn makeTestChoicesDirective(allocator: std.mem.Allocator) !interaction_choices.ChoicesDirective

test "telegram buildGetUpdatesBody includes callback_query" {
    var buf: [256]u8 = undefined;
    const body = try TelegramChannel.buildGetUpdatesBody(&buf, 10, 30);

test "telegram parseCallbackData parses valid format" {
    const parsed = TelegramChannel.parseCallbackData("nc1:abc123:yes") orelse return error.TestUnexpectedResult;

test "telegram parseCallbackData rejects malformed format" {

test "telegram isAuthorizedIdentity enforces group allowlist and ids" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram shouldProcessMessage require_mention fails closed when username unavailable" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram shouldProcessMessage accepts caption mention with utf16 offsets" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram shouldProcessMessage accepts text_mention entity by username" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram shouldProcessMessage accepts text_mention entity by bot user id" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram buildInlineKeyboardJson builds callback_data" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram consumeCallbackSelection valid click is one-shot" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram consumeCallbackSelection rejects owner mismatch" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

test "telegram consumeCallbackSelection rejects expired interaction" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "tok", &.{

// ════════════════════════════════════════════════════════════════════════════
// Draft Streaming Tests
// ════════════════════════════════════════════════════════════════════════════

test "DraftState deinit frees buffer" {
    const allocator = std.testing.allocator;

test "vtableSendEvent chunk accumulates in draft buffer" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent first chunk does not flush immediately" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "shouldSkipDraftSend allows active current draft" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "shouldSkipDraftSend skips missing or stale draft state" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "shouldSkipDraftSend skips while global cooldown is active" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent final cleans up draft state" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent chunk assigns unique draft_id per chat" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent existing chat adopts global draft cooldown" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent new chat inherits global draft cooldown" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent disabled streaming is noop" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent empty chunk is ignored" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "vtableSendEvent final on nonexistent chat is safe" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "ensureDraftStateLocked initializes started_at and flush timestamp" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "beginDraftStateLocked resets timer and rotates draft id" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "finishDraftTurn ignores stale draft id" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "sendDraftChunkForTurn ignores stale draft turn" {
    const allocator = std.testing.allocator;
    var ch = TelegramChannel.init(allocator, "test-token", &.{

test "nextAdaptiveSplitLimit halves toward minimum threshold" {

test "parseTelegramTarget extracts topic suffix" {
    const parsed = parseTelegramTarget("-100123#topic:77");

test "createForumTopicFromTarget rejects empty name" {
    var ch = TelegramChannel.init(std.testing.allocator, "test-token", &.{
