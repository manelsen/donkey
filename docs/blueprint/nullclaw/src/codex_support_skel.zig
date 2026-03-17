const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const auth = @import("auth.zig");

pub const ProbeResult = struct {


pub const DEFAULT_CODEX_MODEL = codex_model_fallbacks[0];
pub const OPENAI_CODEX_CREDENTIAL_KEY = "openai-codex";

const CommandRunResult = struct {

pub fn freeOwnedStrings(allocator: std.mem.Allocator, values: [][]const u8) void

pub fn loadCodexModels(allocator: std.mem.Allocator) ![][]const u8

pub fn probeCodexCli(allocator: std.mem.Allocator) ProbeResult

pub fn probeOpenAiCodex(allocator: std.mem.Allocator) ProbeResult

pub fn hasOpenAiCodexCredential(allocator: std.mem.Allocator) bool

pub fn loadStoredOpenAiCodexCredential(allocator: std.mem.Allocator) ?auth.OAuthToken

pub fn resolveCodexCommand(allocator: std.mem.Allocator) ?[]u8

fn dupeFallbackModels(allocator: std.mem.Allocator) ![][]const u8

fn loadCodexModelsInner(allocator: std.mem.Allocator) ![][]const u8

fn parseCodexModelsFromBytes(allocator: std.mem.Allocator, bytes: []const u8) ![][]const u8

fn containsString(haystack: []const []const u8, needle: []const u8) bool

pub fn loadCodexCliToken(allocator: std.mem.Allocator) ?auth.OAuthToken

fn parseCodexCliTokenFromBytes(allocator: std.mem.Allocator, bytes: []const u8) ?auth.OAuthToken

fn resolveCodexStatePath(allocator: std.mem.Allocator, filename: []const u8) ![]u8

fn resolveHomeRelativePath(allocator: std.mem.Allocator, dir_name: []const u8, filename: []const u8) ![]u8

fn decodeJwtExp(allocator: std.mem.Allocator, token: []const u8) i64

fn resolveFromPath(allocator: std.mem.Allocator, binary_name: []const u8) ?[]u8

fn fileExists(path: []const u8) bool

fn runCommand(allocator: std.mem.Allocator, command: []const u8, args: []const []const u8) !CommandRunResult

test "parseCodexModelsFromBytes parses visible model slugs" {
    const allocator = std.testing.allocator;


test "parseCodexCliTokenFromBytes accepts access token" {


test "parseCodexCliTokenFromBytes keeps expired token when refresh token exists" {

