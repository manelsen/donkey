const std = @import("std");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const isResolvedPathAllowed = @import("path_security.zig").isResolvedPathAllowed;
const UNAVAILABLE_WORKSPACE_SENTINEL = "/__nullclaw_workspace_unavailable__";

/// Git operations tool for structured repository management.
pub const GitTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "git tool name" {
    var gt = GitTool{

test "git tool schema has operation" {
    var gt = GitTool{

test "git rejects missing operation" {
    var gt = GitTool{

test "git rejects unknown operation" {
    var gt = GitTool{

test "git cwd inside workspace works without allowed_paths" {
    var tmp_dir = std.testing.tmpDir(.{

test "git cwd outside workspace without allowed_paths is rejected" {
    var tmp_dir = std.testing.tmpDir(.{

test "git checkout blocks injection" {
    var gt = GitTool{

test "git commit missing message" {
    var gt = GitTool{

test "git commit empty message" {
    var gt = GitTool{

test "git add missing paths" {
    var gt = GitTool{

test "git add empty paths array" {
    var gt = GitTool{

test "git add accepts string paths parameter" {
    var gt = GitTool{

// ── sanitizeGitArgs tests ───────────────────────────────────────────

test "sanitizeGitArgs blocks --exec=cmd" {

test "sanitizeGitArgs blocks --upload-pack=evil" {

test "sanitizeGitArgs blocks --no-verify" {

test "sanitizeGitArgs blocks command substitution $()" {

test "sanitizeGitArgs blocks backtick" {

test "sanitizeGitArgs blocks pipe" {

test "sanitizeGitArgs blocks semicolon" {

test "sanitizeGitArgs blocks redirect" {

test "sanitizeGitArgs blocks -c config injection" {

test "sanitizeGitArgs blocks --pager and --editor" {

test "sanitizeGitArgs blocks --receive-pack" {

test "sanitizeGitArgs allows --oneline" {

test "sanitizeGitArgs allows --stat" {

test "sanitizeGitArgs allows safe branch names" {

test "sanitizeGitArgs allows --cached (not blocked by -c check)" {

// ── truncateCommitMessage tests ─────────────────────────────────────

test "truncateCommitMessage short message unchanged" {
    const msg = "short message";

test "truncateCommitMessage truncates at UTF-8 boundary" {
    // "Éééééé" in UTF-8 is 12 bytes (2 bytes per accented char)
    const msg = "Éééééé ààà!"; // 20 bytes
    const truncated = GitTool.truncateCommitMessage(msg, 10);
    // Should truncate to 10 bytes which is at a clean boundary (5 Cyrillic chars)
    // Must not end in the middle of a multi-byte sequence

test "truncateCommitMessage exact boundary" {
    const msg = "hello";

// ── requiresWriteAccess tests ───────────────────────────────────────

test "requiresWriteAccess returns true for commit" {

test "requiresWriteAccess returns true for push" {

test "requiresWriteAccess returns true for add" {

test "requiresWriteAccess returns false for status" {

test "requiresWriteAccess returns false for diff" {

test "requiresWriteAccess returns false for log" {

// ── Integration: sanitizeGitArgs in execute ─────────────────────────

test "git execute blocks unsafe args in message" {
    var gt = GitTool{

test "git execute blocks unsafe args in paths" {
    var gt = GitTool{

test "git execute blocks unsafe args in paths string" {
    var gt = GitTool{

test "git execute blocks unsafe args in files string" {
    var gt = GitTool{
