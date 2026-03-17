const std = @import("std");

pub const ApiErrorKind = enum {

pub fn kindToError(kind: ApiErrorKind) anyerror

fn sliceEqlAsciiFold(a: []const u8, b: []const u8) bool

fn containsAsciiFold(haystack: []const u8, needle: []const u8) bool

pub fn isRateLimitedText(text: []const u8) bool

pub fn isContextExhaustedText(text: []const u8) bool

pub fn isVisionUnsupportedText(text: []const u8) bool

fn parseStatusCode(value: std.json.Value) ?u16

fn extractErrorFields(root_obj: anytype) ?struct

fn appendBounded(out: []u8, idx: *usize, text: []const u8) void

fn appendFieldPrefix(out: []u8, idx: *usize, wrote_any: *bool, name: []const u8) void

fn appendMessageValue(out: []u8, idx: *usize, raw: []const u8) void

/// Build a compact summary for known provider API errors.
/// Returns null when the payload does not look like an error envelope.
pub fn summarizeKnownApiError(root_obj: anytype, out: []u8) ?[]const u8




/// Classify `{"error": {...}}` payloads used by OpenAI-compatible,
/// Anthropic, and Gemini APIs.
pub fn classifyErrorObject(root_obj: anytype) ?ApiErrorKind

fn classifyTopLevelError(root_obj: anytype) ?ApiErrorKind

/// Classify known API error envelopes.
/// Returns null when no error envelope is present.
pub fn classifyKnownApiError(root_obj: anytype) ?ApiErrorKind

test "classifyKnownApiError detects rate-limit payloads" {
    const body = "{

test "classifyKnownApiError detects context payloads" {
    const body = "{

test "classifyKnownApiError detects vision unsupported payloads" {
    const body = "{

test "classifyKnownApiError returns null for non-error payload" {
    const body = "{

test "summarizeKnownApiError captures status code and message" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, body, .{

test "summarizeKnownApiError returns null for non-error payload" {
    const body = "{
