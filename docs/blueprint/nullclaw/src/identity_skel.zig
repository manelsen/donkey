const std = @import("std");

/// AIEOS v1.1 identity structure — portable AI identity specification.
/// Mirrors ZeroClaw's identity.rs with AIEOS JSON parsing and system prompt generation.
pub const AieosIdentity = struct {

pub const IdentitySection = struct {

pub const Names = struct {

pub const OceanTraits = struct {

pub const PsychologySection = struct {

pub const LinguisticsSection = struct {

pub const MotivationsSection = struct {

pub const CapabilitiesSection = struct {

pub const PhysicalitySection = struct {

pub const HistorySection = struct {

pub const InterestsSection = struct {

/// Load AIEOS identity from a JSON string. All strings are duped into `allocator`.
pub fn parseAieosJson(allocator: std.mem.Allocator, json_content: []const u8) !AieosIdentity

fn parseIdentitySection(allocator: std.mem.Allocator, val: std.json.Value) !IdentitySection

fn parsePsychologySection(allocator: std.mem.Allocator, val: std.json.Value) !PsychologySection

fn parseLinguisticsSection(allocator: std.mem.Allocator, val: std.json.Value) !LinguisticsSection

fn parseMotivationsSection(allocator: std.mem.Allocator, val: std.json.Value) !MotivationsSection

fn parseCapabilitiesSection(allocator: std.mem.Allocator, val: std.json.Value) !CapabilitiesSection

/// Get a string from a JSON object and duplicate it into the allocator.
fn dupeStr(allocator: std.mem.Allocator, val: std.json.Value, key: []const u8) !?[]const u8

fn getFloat(val: std.json.Value, key: []const u8) ?f64

/// Get a string array from a JSON object and duplicate all strings.
fn dupeStrArray(allocator: std.mem.Allocator, val: std.json.Value, key: []const u8) !?[]const []const u8

/// Convert AIEOS identity to a system prompt string.
pub fn aieosToSystemPrompt(allocator: std.mem.Allocator, identity: *const AieosIdentity) ![]const u8

/// Check if AIEOS identity is configured (format is "aieos" with path or inline).
pub fn isAieosConfigured(format: []const u8, aieos_path: ?[]const u8, aieos_inline: ?[]const u8) bool

// ── Tests ────────────────────────────────────────────────────────────

test "parse minimal AIEOS identity" {
    // Use page_allocator since parsed identity is long-lived (no deinit).
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, json);

test "parse full AIEOS identity" {
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, json);

test "parse empty JSON object" {
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, "{

test "aieosToSystemPrompt minimal" {
    const prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "aieosToSystemPrompt empty identity produces header" {
    const prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "aieosToSystemPrompt no sections" {
    const identity = AieosIdentity{

test "isAieosConfigured" {

// ── Additional identity tests ───────────────────────────────────

test "parse AIEOS with physicality section" {
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, json);

test "parse AIEOS with history section" {
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, json);

test "parse AIEOS with interests section" {
    const alloc = std.heap.smp_allocator;
    const identity = try parseAieosJson(alloc, json);

test "parse AIEOS invalid JSON returns error" {
    const alloc = std.heap.smp_allocator;
    const result = parseAieosJson(alloc, "not json");

test "parse AIEOS non-object JSON returns error" {
    const alloc = std.heap.smp_allocator;
    const result = parseAieosJson(alloc, "[1,2,3]");

test "aieosToSystemPrompt with psychology section" {
    const sys_prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "aieosToSystemPrompt with linguistics section" {
    const sys_prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "aieosToSystemPrompt with motivations section" {
    const sys_prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "aieosToSystemPrompt with full name" {
    const sys_prompt = try aieosToSystemPrompt(std.testing.allocator, &identity);

test "isAieosConfigured case sensitive" {
