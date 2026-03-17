const std = @import("std");
const config_mod = @import("config.zig");
const platform = @import("platform.zig");

pub const MutationAction = enum {

pub const MutationOptions = struct {

pub const MutationResult = struct {




pub fn freeMutationResult(allocator: std.mem.Allocator, result: *MutationResult) void

fn defaultConfigDir(allocator: std.mem.Allocator, nullclaw_home_override: ?[]const u8) ![]u8

fn defaultConfigPathFromDir(allocator: std.mem.Allocator, config_dir: []const u8) ![]u8

pub fn defaultConfigPath(allocator: std.mem.Allocator) ![]u8

fn splitPathTokens(allocator: std.mem.Allocator, path: []const u8) ![]const []const u8

fn isAllowedPath(path: []const u8) bool

pub fn pathRequiresRestart(path: []const u8) bool

fn parseValueInput(allocator: std.mem.Allocator, raw_input: []const u8) !std.json.Value

fn ensureObject(value: *std.json.Value, allocator: std.mem.Allocator) *std.json.ObjectMap

fn valueAtPath(root: *std.json.Value, tokens: []const []const u8) ?*std.json.Value

    var current = root;


        const obj = ensureObject(current, allocator);

        const key_copy = try allocator.dupe(u8, token);

    const last = tokens[tokens.len - 1];
    const obj = ensureObject(current, allocator);

    const key_copy = try allocator.dupe(u8, last);

fn unsetAtPath(root: *std.json.Value, tokens: []const []const u8) bool

fn stringifyValue(allocator: std.mem.Allocator, value: ?*std.json.Value) ![]u8

fn readConfigOrDefault(allocator: std.mem.Allocator, config_path: []const u8) !struct

test "defaultConfigDir uses NULLCLAW_HOME override" {
    const allocator = std.testing.allocator;
    const config_dir = try defaultConfigDir(allocator, "/tmp/nullclaw-home");


test "defaultConfigPath appends config filename to NULLCLAW_HOME override" {
    const allocator = std.testing.allocator;
    const config_path = try defaultConfigPathFromDir(allocator, "/tmp/nullclaw-home");

    const expected = try std.fmt.allocPrint(allocator, "/tmp/nullclaw-home{

fn writeAtomic(allocator: std.mem.Allocator, path: []const u8, content: []const u8) !void

fn validateCandidateJson(allocator: std.mem.Allocator, config_path: []const u8, content: []const u8) !void

pub fn getPathValueJson(allocator: std.mem.Allocator, path: []const u8) ![]u8

pub fn validateCurrentConfig(allocator: std.mem.Allocator) !void

    const trimmed_path = std.mem.trim(u8, path, " \t\r\n");

    const config_path = try defaultConfigPath(allocator);

    const current = try readConfigOrDefault(allocator, config_path);

    var arena = std.heap.ArenaAllocator.init(allocator);
    const a = arena.allocator();

    const parsed = std.json.parseFromSlice(std.json.Value, a, current.content, .{

test "pathRequiresRestart detects structural paths" {

test "isAllowedPath accepts channels and memory path" {

test "setAtPath creates nested objects and stores value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const a = arena.allocator();

    var root = std.json.Value{

test "unsetAtPath removes existing key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    const a = arena.allocator();

    var root = std.json.Value{
