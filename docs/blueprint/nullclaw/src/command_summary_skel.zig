const std = @import("std");

pub const Summary = struct {

pub fn summarizeBlockedCommand(command: []const u8) Summary

fn normalizeCommand(command: []const u8) []const u8

fn unwrapMarkdownFence(command: []const u8) ?[]const u8

fn isEnvAssignmentToken(token: []const u8) bool

fn basenameToken(token: []const u8) []const u8

fn safeDisplayLen(token: []const u8) usize

fn displayToken(token: []const u8) []const u8

test "summarizeBlockedCommand skips env assignment values" {
    const summary = summarizeBlockedCommand("OPENAI_API_KEY=sk-secret-123 curl https://example.com");

test "summarizeBlockedCommand unwraps fenced command" {

test "summarizeBlockedCommand uses executable basename" {
    const summary = summarizeBlockedCommand("/usr/local/bin/python3 script.py");

test "summarizeBlockedCommand reports env-only command safely" {
    const summary = summarizeBlockedCommand("FOO=bar BAR=baz");
