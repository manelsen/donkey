//! Max-token resolution for generation limits.
//!
//! Follows the runtime fallback chain:
//!   1) explicit config override
//!   2) best-effort lookup by model/provider id
//!   3) default fallback

const std = @import("std");
const config_types = @import("../config_types.zig");

pub const DEFAULT_MODEL_MAX_TOKENS: u32 = config_types.DEFAULT_MODEL_MAX_TOKENS;

const MaxTokensEntry = struct {

// High-signal model defaults used in onboarding/catalog flows.

// Provider-level fallbacks aligned with current runtime defaults.

fn startsWithIgnoreCase(haystack: []const u8, prefix: []const u8) bool

fn endsWithIgnoreCase(haystack: []const u8, suffix: []const u8) bool

fn isAllDigits(s: []const u8) bool

fn stripDateSuffix(model_id: []const u8) []const u8

fn stripKnownSuffix(model_id: []const u8) []const u8

fn isLegacyGpt4Model(model_id: []const u8) bool

fn lookupTable(table: []const MaxTokensEntry, key: []const u8) ?u32

fn splitProviderModel(model_ref: []const u8) struct

fn inferFromModelPattern(model_id: []const u8) ?u32

fn lookupModelCandidates(model_id_raw: []const u8) ?u32

pub fn lookupModelMaxTokens(model_ref_raw: []const u8) ?u32

pub fn resolveMaxTokens(max_tokens_override: ?u32, model_ref: []const u8) u32

test "resolveMaxTokens honors explicit override first" {
    const resolved = resolveMaxTokens(512, "openai/gpt-4.1-mini");

test "lookupModelMaxTokens resolves model and nested provider refs" {

test "lookupModelMaxTokens keeps legacy and turbo gpt-4 variants distinct" {

test "lookupModelMaxTokens strips date suffixes and latest aliases" {

test "lookupModelMaxTokens provider fallback handles lower ceilings" {

test "resolveMaxTokens falls back to global default" {
    const resolved = resolveMaxTokens(null, "unknown-provider/unknown-model");
