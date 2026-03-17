const std = @import("std");

pub fn pathStartsWith(path: []const u8, prefix: []const u8) bool

fn normalizeWindowsPrefix(path: []const u8) []const u8

fn isWindowsPathSeparator(c: u8) bool

fn windowsPrefixEquals(path: []const u8, prefix: []const u8) bool

test "path_prefix exact and nested match" {

test "path_prefix rejects partial segment" {

test "path_prefix accepts separator-terminated roots" {

test "path_prefix windows case-insensitive and separators" {
    if (comptime @import("builtin").os.tag != .windows) return;
