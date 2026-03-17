const std = @import("std");
const root = @import("root.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;
const ChatMessage = root.ChatMessage;

/// Provider that delegates to the `claude` CLI (Claude Code).
///
/// Fresh sessions seed Claude with the full NullClaw transcript, while resumed
/// sessions send only the new message delta since the last successful turn.
pub const ClaudeCliProvider = struct {



fn transcriptResumeDeltaStart(existing: []const u64, messages: []const ChatMessage, current: []const u64) ?usize

fn extractSystemPrompt(messages: []const ChatMessage) ?[]const u8

fn hashChatMessage(msg: ChatMessage) u64

fn hashAssistantResponse(content: []const u8) u64

fn collectMessageHashes(allocator: std.mem.Allocator, messages: []const ChatMessage) ![]u64

fn renderPromptMessages(allocator: std.mem.Allocator, messages: []const ChatMessage, start_index: usize) ![]u8

fn runClaudeCommand(allocator: std.mem.Allocator, opts: ClaudeCliProvider.ClaudeCommandOptions) !ClaudeCliProvider.ClaudeCommandResult

fn parseStreamJson(allocator: std.mem.Allocator, output: []const u8) !ClaudeCliProvider.ClaudeCommandResult

fn checkCliAvailable(allocator: std.mem.Allocator, cli_name: []const u8) !void

fn checkCliVersion(allocator: std.mem.Allocator, cli_name: []const u8) !void

test "ClaudeCliProvider.getNameImpl returns claude-cli" {
    const vtable = ClaudeCliProvider.vtable;
    var dummy: u8 = 0;

test "extractSystemPrompt returns first system message" {

test "extractSystemPrompt returns null when absent" {

test "renderPromptMessages renders transcript without system" {

    const rendered = try renderPromptMessages(std.testing.allocator, &msgs, 0);


test "renderPromptMessages respects delta start" {

    const rendered = try renderPromptMessages(std.testing.allocator, &msgs, 2);


test "renderPromptMessages rejects all-system delta" {

test "buildSessionPlan resumes only when transcript is still a prefix" {
    var state = ClaudeCliProvider.SessionState{

test "buildSessionPlan resets on diverged history" {
    var state = ClaudeCliProvider.SessionState{

test "buildSessionPlan resets on idle timeout" {
    var state = ClaudeCliProvider.SessionState{

test "buildSessionPlan tolerates normalized assistant history mismatch" {
    var state = ClaudeCliProvider.SessionState{

test "deleteSessionStateLocked removes stored session state" {




test "SessionState updateTranscript appends assistant response hash" {
    var state = ClaudeCliProvider.SessionState{

test "parseStreamJson extracts result and session id from start event" {
    const result = try parseStreamJson(std.testing.allocator, input);

test "parseStreamJson extracts session id from system event" {
    const result = try parseStreamJson(std.testing.allocator, input);

test "parseStreamJson no result returns error" {

test "parseStreamJson handles invalid json lines gracefully" {
    const result = try parseStreamJson(std.testing.allocator, input);

test "ClaudeCliProvider vtable has correct function pointers" {
    const vtable = ClaudeCliProvider.vtable;
    var dummy: u8 = 0;

test "ClaudeCliProvider.init returns CliNotFound for missing binary" {
    const result = checkCliAvailable(std.testing.allocator, "nonexistent_binary_xyzzy_12345");

test "ClaudeCliProvider default model is claude-opus-4-6" {
