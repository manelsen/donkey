const std = @import("std");

/// Extract a string field value from a JSON blob (minimal parser — no allocations).
pub fn parseStringField(json: []const u8, key: []const u8) ?[]const u8

/// Extract a boolean field value from a JSON blob.
pub fn parseBoolField(json: []const u8, key: []const u8) ?bool

/// Extract an integer field value from a JSON blob.
pub fn parseIntField(json: []const u8, key: []const u8) ?i64

/// Extract an unsigned integer field value from a JSON blob.
pub fn parseUintField(json: []const u8, key: []const u8) ?u64

test "json_miniparse parseStringField basic" {
    const json = "{

test "json_miniparse parseBoolField values" {

test "json_miniparse parseIntField supports signed numbers" {

test "json_miniparse parseUintField supports positive numbers" {

test "json_miniparse missing fields return null" {
