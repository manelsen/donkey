const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Browser open tool — opens an approved HTTPS URL in the default browser.
/// macOS: `open URL`
/// Linux: `xdg-open URL`
/// Validates URL against an allowlist of domains.
pub const BrowserOpenTool = struct {

fn isLocalOrPrivate(host: []const u8) bool

fn hostMatchesAllowlist(host: []const u8, allowed: []const []const u8) bool

// ── Tests ───────────────────────────────────────────────────────────

test "browser_open tool name" {
    var bo = BrowserOpenTool{

test "browser_open tool description not empty" {
    var bo = BrowserOpenTool{

test "browser_open tool schema has url" {
    var bo = BrowserOpenTool{

test "browser_open missing url returns error" {
    const domains = [_][]const u8{

test "browser_open rejects http" {
    const domains = [_][]const u8{

test "browser_open rejects empty allowlist" {
    var bo = BrowserOpenTool{

test "browser_open rejects non-allowlisted domain" {
    const domains = [_][]const u8{

test "browser_open rejects localhost" {
    const domains = [_][]const u8{

test "browser_open rejects private ip" {
    const domains = [_][]const u8{

test "isLocalOrPrivate detects localhost" {

test "hostMatchesAllowlist exact and subdomain" {
    const domains = [_][]const u8{

test "browser_open tool spec" {
    var bo = BrowserOpenTool{