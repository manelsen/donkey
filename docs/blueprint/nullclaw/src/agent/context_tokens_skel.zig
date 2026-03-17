//! Context-token resolution for agent compaction.
//!
//! Follows the runtime fallback chain:
//!   1) explicit config override
//!   2) best-effort lookup by model id
//!   3) default fallback

const std = @import("std");
const config_types = @import("../config_types.zig");

pub const DEFAULT_CONTEXT_TOKENS: u64 = config_types.DEFAULT_AGENT_TOKEN_LIMIT;

const ContextWindowEntry = struct {

// Model-specific defaults for high-signal IDs used by onboarding/catalog flows.

// Provider-level fallbacks aligned with current runtime defaults where available.

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool

fn isAllDigits(s: []const u8) bool

fn stripDateSuffix(model_id: []const u8) []const u8

fn stripKnownSuffix(model_id: []const u8) []const u8

fn isLegacyGpt4Model(model_id: []const u8) bool

fn lookupTable(table: []const ContextWindowEntry, key: []const u8) ?u64

fn splitProviderModel(model_ref: []const u8) struct

fn inferFromModelPattern(model_id: []const u8) ?u64

fn lookupModelCandidates(model_id_raw: []const u8) ?u64

pub fn lookupContextTokens(model_ref_raw: []const u8) ?u64

pub fn resolveContextTokens(token_limit_override: ?u64, model_ref: []const u8) u64

test "resolveContextTokens honors explicit override first" {
    const resolved = resolveContextTokens(42_000, "openai/gpt-4.1-mini");

test "lookupContextTokens resolves known model ids" {

test "lookupContextTokens keeps legacy and turbo gpt-4 variants distinct" {

test "lookupContextTokens handles nested provider refs" {

test "lookupContextTokens strips date suffixes" {

test "lookupContextTokens falls back to provider defaults" {

test "resolveContextTokens falls back to global default" {
    const resolved = resolveContextTokens(null, "unknown-provider/unknown-model");
