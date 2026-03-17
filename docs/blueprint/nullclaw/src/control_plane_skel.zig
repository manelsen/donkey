const std = @import("std");

pub const SlashCommand = struct {

pub const TelegramBotCommandScope = enum {

pub const TelegramBotCommandOptions = struct {


const TelegramBotCommand = struct {






    var out: std.ArrayListUnmanaged(u8) = .empty;

    var first = true;
    const include_topic_command = opts.scope != .all_private_chats and opts.include_topic_command;
    const include_topics_command = opts.scope != .all_private_chats and opts.include_topics_command;

    var out: std.ArrayListUnmanaged(u8) = .empty;


pub fn parseSlashCommand(message: []const u8) ?SlashCommand

pub fn isSlashName(cmd: SlashCommand, expected: []const u8) bool

pub fn isStopCommandName(name: []const u8) bool

pub fn isStopLikeCommand(content: []const u8) bool

fn slashCommandName(raw_name: []const u8) []const u8

test "parseSlashCommand strips bot mention from command name" {
    const parsed = parseSlashCommand("/model@nullclaw_bot openrouter/inception/mercury") orelse return error.TestExpectedEqual;

test "parseSlashCommand strips bot mention with colon separator" {
    const parsed = parseSlashCommand("/model@nullclaw_bot: gpt-5.2") orelse return error.TestExpectedEqual;

test "isStopLikeCommand matches stop and abort variants" {

test "isStopLikeCommand rejects non-control commands" {

test "telegram bot command payload includes grouped menu commands" {
    const json = try buildTelegramBotCommandsJson(std.testing.allocator, .{

test "buildTelegramBotCommandsJson omits topic commands when disabled" {


test "buildTelegramBotCommandsJson omits bind command when disabled" {


test "buildTelegramBotCommandsJson omits topic commands in private scope" {


test "buildTelegramDeleteBotCommandsJson includes scope" {
    const json = try buildTelegramDeleteBotCommandsJson(std.testing.allocator, .all_group_chats);

