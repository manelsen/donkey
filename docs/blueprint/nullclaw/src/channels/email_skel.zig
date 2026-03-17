const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");

/// Email channel — IMAP polling for inbound, SMTP for outbound.
pub const EmailChannel = struct {
    /// Tracks last Message-ID per sender for In-Reply-To/References headers.

/// Bounded dedup set that evicts oldest entries when capacity is reached.
pub const BoundedSeenSet = struct {

/// Strip HTML tags from content (basic).
pub fn stripHtml(allocator: std.mem.Allocator, html: []const u8) ![]u8

/// Check if subject already has a "Re:" prefix (case-insensitive).
pub fn hasReplyPrefix(subject: []const u8) bool

/// Return the reply subject: if it already starts with "Re:" (case-insensitive),
/// return as-is; otherwise return as-is (callers should use replySubjectAlloc for prefix).
/// This non-allocating version is used when the subject is written via format string.
pub fn replySubject(original: []const u8) []const u8

/// Allocating version of replySubject — always returns "Re: <subject>" if not already prefixed.
pub fn replySubjectAlloc(allocator: std.mem.Allocator, original: []const u8) ![]u8

/// Decode RFC 2047 encoded-word headers.
/// Supports =?CHARSET?B?BASE64?= and =?CHARSET?Q?QUOTED-PRINTABLE?=.
/// Non-encoded text is passed through as-is.
pub fn decodeRfc2047(allocator: std.mem.Allocator, encoded: []const u8) ![]u8

const EncodedWord = struct {

/// Parse an RFC 2047 encoded-word starting at the given slice.
/// Format: =?charset?encoding?payload?=
fn parseEncodedWord(s: []const u8) ?EncodedWord

fn hexDigit(c: u8) ?u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "bounded seen set insert and contains" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 10);

test "bounded seen set rejects duplicates" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 10);

test "bounded seen set evicts oldest at capacity" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 3);


test "bounded seen set capacity one" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 1);

test "strip html basic" {
    const allocator = std.testing.allocator;
    const result = try stripHtml(allocator, "<p>Hello <b>world</b>!</p>");

test "strip html no tags" {
    const allocator = std.testing.allocator;
    const result = try stripHtml(allocator, "plain text");

// ════════════════════════════════════════════════════════════════════════════
// Additional Email Tests (ported from ZeroClaw Rust)
// ════════════════════════════════════════════════════════════════════════════

test "bounded seen set evicts in fifo order" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 2);


test "email sender allowed case insensitive full address" {
    const senders = [_][]const u8{

test "email sender domain with @ case insensitive" {
    const senders = [_][]const u8{

test "email sender multiple senders" {
    const senders = [_][]const u8{

test "email config defaults" {
    const config = config_types.EmailConfig{

test "strip html nested tags" {
    const allocator = std.testing.allocator;
    const result = try stripHtml(allocator, "<div><p>Hello</p><br/><p>World</p></div>");

test "strip html empty input" {
    const allocator = std.testing.allocator;
    const result = try stripHtml(allocator, "");

test "strip html only tags" {
    const allocator = std.testing.allocator;
    const result = try stripHtml(allocator, "<br/><hr/><img src=\"x\"/>");

test "bounded seen set empty contains false" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 10);

test "bounded seen set large capacity" {
    const allocator = std.testing.allocator;
    var set = BoundedSeenSet.init(allocator, 100);
    var i: usize = 0;
        var buf: [20]u8 = undefined;
        const key = std.fmt.bufPrint(&buf, "key_{

test "email sender wildcard with specific" {
    const senders = [_][]const u8{

test "email sender short address not domain match" {
    // An address shorter than the domain should not match
    const senders = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// Consent Gates Tests
// ════════════════════════════════════════════════════════════════════════════

test "consent granted default is true" {
    const config = config_types.EmailConfig{

test "consent not granted blocks send" {
    var ch = EmailChannel.init(std.testing.allocator, .{

test "consent granted allows send attempt" {
    // With consent but invalid host, we expect SmtpConnectError (not ConsentNotGranted)
    const result = ch.sendMessage("test@example.com", "hello");

// ════════════════════════════════════════════════════════════════════════════
// In-Reply-To / References Tests
// ════════════════════════════════════════════════════════════════════════════

test "track message id stores and retrieves" {
    const allocator = std.testing.allocator;
    var ch = EmailChannel.init(allocator, .{

test "track message id overwrites previous" {
    const allocator = std.testing.allocator;
    var ch = EmailChannel.init(allocator, .{

test "track message id multiple senders" {
    const allocator = std.testing.allocator;
    var ch = EmailChannel.init(allocator, .{

// ════════════════════════════════════════════════════════════════════════════
// Subject Tracking Tests
// ════════════════════════════════════════════════════════════════════════════

test "hasReplyPrefix detects Re prefix" {

test "hasReplyPrefix rejects non-Re" {

test "replySubjectAlloc adds prefix" {
    const allocator = std.testing.allocator;
    const result = try replySubjectAlloc(allocator, "Hello World");

test "replySubjectAlloc preserves existing Re" {
    const allocator = std.testing.allocator;
    const result = try replySubjectAlloc(allocator, "Re: Hello World");

test "replySubjectAlloc empty subject" {
    const allocator = std.testing.allocator;
    const result = try replySubjectAlloc(allocator, "");

test "replySubjectAlloc case insensitive RE" {
    const allocator = std.testing.allocator;
    const result = try replySubjectAlloc(allocator, "RE: Already");

// ════════════════════════════════════════════════════════════════════════════
// RFC 2047 Decoding Tests
// ════════════════════════════════════════════════════════════════════════════

test "decodeRfc2047 base64 utf8" {
    const allocator = std.testing.allocator;
    // "Hello" in base64 = "SGVsbG8="
    const result = try decodeRfc2047(allocator, "=?UTF-8?B?SGVsbG8=?=");

test "decodeRfc2047 quoted printable" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "=?UTF-8?Q?Hello_World?=");

test "decodeRfc2047 quoted printable hex escape" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "=?UTF-8?Q?caf=C3=A9?=");

test "decodeRfc2047 plain text passthrough" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "Just plain text");

test "decodeRfc2047 mixed encoded and plain" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "Hello =?UTF-8?B?V29ybGQ=?= !");

test "decodeRfc2047 empty input" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "");

test "decodeRfc2047 case insensitive encoding" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "=?utf-8?b?SGVsbG8=?=");

test "decodeRfc2047 quoted printable underscore to space" {
    const allocator = std.testing.allocator;
    const result = try decodeRfc2047(allocator, "=?UTF-8?Q?Re:_Your_Order?=");

test "parseEncodedWord valid base64" {
    const ew = parseEncodedWord("=?UTF-8?B?SGVsbG8=?=").?;

test "parseEncodedWord invalid returns null" {

test "hexDigit valid digits" {

test "hexDigit invalid returns null" {

// ════════════════════════════════════════════════════════════════════════════
// Mark-as-Seen Test
// ════════════════════════════════════════════════════════════════════════════

test "markMessageSeen method exists" {
    // Verify the method signature compiles correctly
    var ch = EmailChannel.init(std.testing.allocator, .{
