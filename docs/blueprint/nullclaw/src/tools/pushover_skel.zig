const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;
const fs_compat = @import("../fs_compat.zig");
const urlEncode = @import("web_search_providers/common.zig").urlEncode;
const http_util = @import("../http_util.zig");

const PUSHOVER_API_URL = "https://api.pushover.net/1/messages.json";

/// Pushover push notification tool.
/// Sends notifications via the Pushover API. Requires PUSHOVER_TOKEN and
/// PUSHOVER_USER_KEY in the workspace .env file.
pub const PushoverTool = struct {

// ── Tests ───────────────────────────────────────────────────────────

test "pushover tool name" {
    var pt = PushoverTool{

test "pushover schema has message required" {
    var pt = PushoverTool{

test "pushover execute missing message" {
    var pt = PushoverTool{

test "pushover execute empty message" {
    var pt = PushoverTool{

test "pushover priority -3 rejected" {
    var pt = PushoverTool{

test "pushover priority 5 rejected" {
    var pt = PushoverTool{

test "pushover priority 2 accepted (credential error expected)" {
    var pt = PushoverTool{

test "pushover priority -2 accepted (credential error expected)" {
    var pt = PushoverTool{

test "parseEnvValue strips export prefix" {
    // parseEnvValue doesn't strip export itself — that's done in getCredentials.
    // But it does strip quotes and inline comments.
    // For this test, we test what parseEnvValue does with the value portion.
    const result = PushoverTool.parseEnvValue("  myvalue  ");

test "parseEnvValue strips quotes" {
    const dq = PushoverTool.parseEnvValue("\"quotedvalue\"");
    const sq = PushoverTool.parseEnvValue("'singlequoted'");

test "parseEnvValue strips inline comment" {
    const result = PushoverTool.parseEnvValue("myvalue # this is a comment");

test "pushover schema has priority and sound" {
    var pt = PushoverTool{

test "getCredentials reads token and user_key from .env file" {
    var tmp_dir = std.testing.tmpDir(.{

test "getCredentials reads exported and quoted values" {
    var tmp_dir = std.testing.tmpDir(.{

test "getCredentials missing token returns error" {
    var tmp_dir = std.testing.tmpDir(.{

test "getCredentials missing user_key returns error" {
    var tmp_dir = std.testing.tmpDir(.{

test "getCredentials missing .env returns error" {
    var pt = PushoverTool{
