const std = @import("std");

pub const START_TAG = "<nc_choices>";
pub const END_TAG = "</nc_choices>";
pub const MAX_OPTIONS: usize = 6;
pub const MIN_OPTIONS: usize = 2;
pub const MAX_ID_LEN: usize = 24;
pub const MAX_LABEL_LEN: usize = 64;
pub const MAX_SUBMIT_TEXT_LEN: usize = 256;

pub const ChoiceOption = struct {

pub const ChoicesDirective = struct {

pub const ParsedAssistantChoices = struct {

const ChoicesBlockSpan = struct {

pub fn parseAssistantChoices(allocator: std.mem.Allocator, text: []const u8) !ParsedAssistantChoices

fn findChoicesBlock(text: []const u8) ?ChoicesBlockSpan

fn stripChoicesBlock(allocator: std.mem.Allocator, text: []const u8, span: ChoicesBlockSpan) ![]u8

fn synthesizeFallbackText(allocator: std.mem.Allocator, options: []const ChoiceOption) ![]u8

fn parseChoicesDirective(allocator: std.mem.Allocator, json_payload: []const u8) !?ChoicesDirective

fn isValidChoiceId(id: []const u8) bool

test "choices parse valid directive and strip block" {
    const allocator = std.testing.allocator;


test "choices parse invalid json returns no choices and strips block when visible text remains" {
    const allocator = std.testing.allocator;


test "choices parse invalid json keeps original text when stripping would make it empty" {
    const allocator = std.testing.allocator;


test "choices parse rejects duplicate ids" {
    const allocator = std.testing.allocator;

test "choices parse rejects too many options" {
    const allocator = std.testing.allocator;
    var parsed = try parseAssistantChoices(allocator, text);

test "choices parse synthesizes fallback text when visible text empty" {
    const allocator = std.testing.allocator;

test "choices parse rejects invalid id chars" {
    const allocator = std.testing.allocator;
