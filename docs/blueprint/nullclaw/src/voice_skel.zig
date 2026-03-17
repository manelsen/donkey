//! Voice transcription via OpenAI-compatible STT APIs (Groq/OpenAI/Telnyx).
//!
//! Reads an audio file, builds a multipart/form-data POST request,
//! and sends it to the configured transcription endpoint. Returns the
//! transcribed text as an owned slice.

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const json_util = @import("json_util.zig");
const http_util = @import("http_util.zig");

const log = std.log.scoped(.voice);

fn getPid() i32

pub const TranscribeOptions = struct {


// ════════════════════════════════════════════════════════════════════════════
// Transcriber vtable interface
// ════════════════════════════════════════════════════════════════════════════

pub const Transcriber = struct {

pub const WhisperTranscriber = struct {

/// Resolve transcription endpoint for a given provider name.
pub fn resolveTranscriptionEndpoint(provider: []const u8, explicit_endpoint: ?[]const u8) []const u8

/// Transcribe an audio file using the Groq Whisper API.
///
/// Reads the file at `file_path`, builds a multipart/form-data request,
/// POSTs to the Groq transcription endpoint, and returns the transcribed text.
/// Caller owns the returned slice.
    // Generate random boundary (16 hex chars)
    const boundary = generateBoundary() catch return error.BoundaryGenerationFailed;

    // Build temp file path (platform-aware temp dir)
    const tmp_dir = platform.getTempDir(allocator) catch return error.FileReadFailed;
    var tmp_path_buf: [256]u8 = undefined;
    var tmp_fbs = std.io.fixedBufferStream(&tmp_path_buf);
    const tmp_path_len = tmp_fbs.pos;
    const tmp_path: [:0]const u8 = tmp_path_buf[0..tmp_path_len :0];

    // Write multipart body directly to temp file (avoids holding file_data + body in memory)

    // Build headers
    var content_type_buf: [128]u8 = undefined;
    var ct_fbs = std.io.fixedBufferStream(&content_type_buf);
    const content_type_hdr = ct_fbs.getWritten();

    var auth_buf: [256]u8 = undefined;
    var auth_fbs = std.io.fixedBufferStream(&auth_buf);
    const auth_hdr = auth_fbs.getWritten();

    // POST via curl using --data-binary @tempfile

    // Parse {"text":"..."} from response

/// Generate a random 32-character hex boundary string.
fn generateBoundary() ![32]u8

/// Build the multipart/form-data body.
    var body: std.ArrayListUnmanaged(u8) = .empty;

    // Part: file

    // Part: model

    // Part: language (optional)

    // Closing boundary


/// Write multipart/form-data directly to a temp file, streaming the audio file
/// through without building the full body in memory.
/// This avoids holding both file_data and multipart body in RAM simultaneously.
    const tmp_file = try std.fs.createFileAbsolute(tmp_path, .{

/// Parse the "text" field from a JSON response like {"text":"transcribed text here"}.
fn parseTranscriptionText(allocator: std.mem.Allocator, json_resp: []const u8) ![]const u8

/// HTTP POST via curl subprocess, reading body from a file on disk.
/// Used for multipart/form-data where body has already been written to a temp file.
    // Build data-binary arg: @/path/to/file
    var data_arg_buf: [300]u8 = undefined;
    var data_fbs = std.io.fixedBufferStream(&data_arg_buf);
    const data_arg = data_fbs.getWritten();

    var argv_buf: [32][]const u8 = undefined;
    var argc: usize = 0;




    var child = std.process.Child.init(argv_buf[0..argc], allocator);


    const stdout = child.stdout.?.readToEndAlloc(allocator, 4 * 1024 * 1024) catch return error.CurlReadError;

    const term = child.wait() catch return error.CurlWaitError;


// ════════════════════════════════════════════════════════════════════════════
// Telegram Voice Integration
// ════════════════════════════════════════════════════════════════════════════

/// Download a Telegram voice/audio file and transcribe it.
/// Returns the transcribed text, or null if transcription is unavailable
/// (no Transcriber configured or file download fails).
    const transcr = t orelse return null;

    // 1. Call getFile to get file_path

    // 2. Download file via Telegram API
        // Clean up temp file

    // 3. Transcribe via vtable


/// Call Telegram getFile API and extract the file_path from the response.
fn getFilePath(allocator: std.mem.Allocator, bot_token: []const u8, file_id: []const u8) ![]u8

/// Download a file from Telegram and save to temp dir. Returns the local path (owned).
fn downloadTelegramFile(allocator: std.mem.Allocator, bot_token: []const u8, tg_file_path: []const u8) ![]u8

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "voice TranscribeOptions defaults" {
    const opts = TranscribeOptions{

test "voice TranscribeOptions custom" {

test "voice generateBoundary produces 32 hex chars" {
    const boundary = try generateBoundary();

test "voice generateBoundary produces different values" {
    const b1 = try generateBoundary();
    const b2 = try generateBoundary();
    // Extremely unlikely to be equal

test "voice buildMultipartBody structure" {
    const allocator = std.testing.allocator;
    const boundary = "abcdef0123456789abcdef0123456789";
    const file_data = "fake audio data";

    const body = try buildMultipartBody(allocator, boundary, file_data, .{

test "voice buildMultipartBody with language" {
    const allocator = std.testing.allocator;
    const boundary = "abcdef0123456789abcdef0123456789";

    const body = try buildMultipartBody(allocator, boundary, "data", .{

test "voice buildMultipartBody without language" {
    const allocator = std.testing.allocator;
    const boundary = "abcdef0123456789abcdef0123456789";

    const body = try buildMultipartBody(allocator, boundary, "data", .{

test "voice parseTranscriptionText valid" {
    const allocator = std.testing.allocator;
    const json = "{

test "voice parseTranscriptionText unicode" {
    const allocator = std.testing.allocator;
    const json = "{

test "voice parseTranscriptionText missing field" {
    const allocator = std.testing.allocator;
    const result = parseTranscriptionText(allocator, "{

test "voice parseTranscriptionText invalid json" {
    const allocator = std.testing.allocator;
    const result = parseTranscriptionText(allocator, "not json");

test "voice parseTranscriptionText non-string text" {
    const allocator = std.testing.allocator;
    const result = parseTranscriptionText(allocator, "{

test "voice parseTranscriptionText empty text" {
    const allocator = std.testing.allocator;
    const text = try parseTranscriptionText(allocator, "{

test "voice transcribeFile returns error for nonexistent file" {
    const allocator = std.testing.allocator;
    const result = transcribeFile(allocator, "fake_key", "https://api.groq.com/openai/v1/audio/transcriptions", "/nonexistent/path/audio.ogg", .{

test "voice transcribeTelegramVoice returns null without transcriber" {
    // No transcriber configured, so should return null
    const result = transcribeTelegramVoice(std.testing.allocator, "fake:token", "fake_file_id", null);

test "voice WhisperTranscriber stores fields" {
    // Vtable dispatches
    const t = wt.transcriber();

test "voice resolveTranscriptionEndpoint groq" {

test "voice resolveTranscriptionEndpoint openai" {

test "voice resolveTranscriptionEndpoint explicit" {

test "voice resolveTranscriptionEndpoint unknown falls back to groq" {
    // Unknown providers fall back to the Groq-compatible endpoint

test "voice resolveTranscriptionEndpoint telnyx" {
