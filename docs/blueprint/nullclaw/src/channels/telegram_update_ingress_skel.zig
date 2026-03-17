const std = @import("std");

pub const IdentityScratch = struct {

pub const UserIdentity = struct {

pub const ChatContext = struct {

pub const DocumentInfo = struct {

pub const VoiceOrAudioKind = enum {

pub const VoiceOrAudioInfo = struct {

pub fn updateId(update: std.json.Value) ?i64

pub fn callbackQuery(update: std.json.Value) ?std.json.Value

pub fn updateMessage(update: std.json.Value) ?std.json.Value

pub fn callbackMessage(callback_query: std.json.Value) ?std.json.Value

pub fn messageSender(message: std.json.Value, scratch: *IdentityScratch) ?UserIdentity

pub fn callbackSender(callback_query: std.json.Value, scratch: *IdentityScratch) ?UserIdentity

pub fn messageChatContext(message: std.json.Value, scratch: *IdentityScratch) ?ChatContext

pub fn callbackMessageContext(callback_query: std.json.Value, scratch: *IdentityScratch) ?ChatContext

pub fn voiceOrAudioFileId(message: std.json.Value) ?[]const u8

pub fn voiceOrAudioInfo(message: std.json.Value) ?VoiceOrAudioInfo

pub fn photoFileId(message: std.json.Value) ?[]const u8

pub fn documentInfo(message: std.json.Value) ?DocumentInfo

pub fn text(message: std.json.Value) ?[]const u8

pub fn caption(message: std.json.Value) ?[]const u8

pub fn textOrCaption(allocator: std.mem.Allocator, message: std.json.Value) ?[]u8

fn mediaFileId(message: std.json.Value, key: []const u8) ?[]const u8

const MediaInfo = struct {

fn mediaInfo(message: std.json.Value, key: []const u8) ?MediaInfo

fn userIdentity(from_obj: std.json.Value, scratch: *IdentityScratch) ?UserIdentity

fn parseUserId(from_obj: std.json.Value, scratch: *IdentityScratch) ?[]const u8

fn preferredIdentity(username: []const u8, user_id: ?[]const u8) []const u8

fn objectField(value: std.json.Value, key: []const u8) ?std.json.Value

fn stringField(value: std.json.Value, key: []const u8) ?[]const u8

fn integerField(value: std.json.Value, key: []const u8) ?i64

fn messageThreadId(message: std.json.Value) ?i64

test "telegram update ingress parses user identity" {

    var scratch: IdentityScratch = .{

test "telegram update ingress parses chat context" {

    var scratch: IdentityScratch = .{

test "telegram update ingress infers thread id from topic reply root" {

    var scratch: IdentityScratch = .{

test "telegram update ingress falls back from text to caption" {
    const allocator = std.testing.allocator;

    const content = textOrCaption(allocator, parsed.value) orelse return error.TestExpectedEqual;

test "telegram update ingress parses document metadata" {

    const doc = documentInfo(parsed.value) orelse return error.TestExpectedEqual;

test "telegram update ingress parses voice and audio metadata" {

    const voice_info = voiceOrAudioInfo(voice_parsed.value) orelse return error.TestExpectedEqual;


    const audio_info = voiceOrAudioInfo(audio_parsed.value) orelse return error.TestExpectedEqual;
