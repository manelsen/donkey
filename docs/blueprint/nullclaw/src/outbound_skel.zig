const std = @import("std");

pub const AttachmentKind = enum {

pub const Attachment = struct {

pub const Choice = struct {

pub const Payload = struct {

pub fn has_legacy_attachment_markers(text: []const u8) bool

test "outbound has_legacy_attachment_markers detects supported markers" {

test "outbound has_legacy_attachment_markers ignores plain text" {
