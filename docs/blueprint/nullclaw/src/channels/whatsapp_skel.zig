const std = @import("std");
const root = @import("root.zig");
const config_types = @import("../config_types.zig");

/// WhatsApp channel — uses WhatsApp Business Cloud API.
/// Operates in webhook mode (push-based); messages received via gateway endpoint.
pub const WhatsAppChannel = struct {

pub const ParsedMessage = struct {

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "whatsapp verify token" {
    const ch = WhatsAppChannel.init(std.testing.allocator, "tok", "123", "my-verify", &.{

test "whatsapp normalize phone" {
    var buf: [32]u8 = undefined;

test "whatsapp parse empty payload" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse invalid shapes returns empty" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse valid text message" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse unauthorized number filtered" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp group open bypasses allow_from" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp group allowlist falls back to allow_from" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp group allowlist blocks when allowlists are empty" {
    const allocator = std.testing.allocator;
    const ch = WhatsAppChannel.init(allocator, "tok", "123", "ver", &.{

test "whatsapp parse non-text message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// Edge Cases — Comprehensive coverage (ported from ZeroClaw Rust tests)
// ════════════════════════════════════════════════════════════════════════════

test "whatsapp parse missing entry array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse missing changes array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse missing value" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse missing messages array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse malformed message types are ignored" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp download media malformed messages type returns null" {
    const allocator = std.testing.allocator;

test "whatsapp parse missing from field" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse missing text body" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse null text body" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse invalid timestamp uses current" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse missing timestamp uses current" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse multiple messages" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse multiple entries" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse multiple changes" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse status update ignored" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse audio message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse video message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse document message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse sticker message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse location message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse contacts message skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse mixed authorized unauthorized" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse unicode message" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse whitespace only message passes through" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp number allowed multiple numbers" {
    const nums = [_][]const u8{

test "whatsapp number allowed case sensitive" {
    const nums = [_][]const u8{

test "whatsapp parse phone already has plus" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse normalizes phone with plus" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp channel fields stored correctly" {
    const nums = [_][]const u8{

test "whatsapp parse empty messages array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse empty entry array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse empty changes array" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse newlines preserved" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp parse special characters" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp empty text skipped" {
    const allocator = std.testing.allocator;
    const nums = [_][]const u8{

test "whatsapp normalize phone empty" {
    var buf: [32]u8 = undefined;

test "whatsapp normalize phone buffer too small" {
    var buf: [2]u8 = undefined;
    // Phone "123" needs 4 bytes ("+123"), but buf is only 2 bytes
