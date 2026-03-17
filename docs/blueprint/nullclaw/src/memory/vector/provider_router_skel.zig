//! Provider router — embedding route selection, fallback chain, and auto-provider orchestration.
//!
//! Implements E-P1 (auto/fallback) and route-based provider selection from the
//! embedding provider spec (reference/memory/embeddings.md).
//!
//! The router wraps multiple EmbeddingProviders and exposes the same vtable interface.
//! On embed() failure, it walks a fallback chain until one succeeds or all fail.
//!
//! Route resolution:
//!   - If a model name starts with "hint:", resolve to a matching route
//!   - Route fields override the base embedder config
//!   - Unknown hints fall back to the base provider

const std = @import("std");
const embeddings = @import("embeddings.zig");
const EmbeddingProvider = embeddings.EmbeddingProvider;

const log = std.log.scoped(.provider_router);

// ── Error classification ──────────────────────────────────────────

pub const ErrorClass = enum {
    /// Authentication/authorization failure — do not retry, skip provider.
    /// Transient failure (network, timeout, rate limit) — may retry.
    /// Permanent failure (bad request, unsupported model) — skip provider.

/// Classify an embedding error for fallback decisions.
pub fn classifyError(err: anyerror) ErrorClass

// ── Embedding route ───────────────────────────────────────────────

pub const EmbeddingRoute = struct {

// ── Provider router ───────────────────────────────────────────────

pub const ProviderRouter = struct {
    /// Primary provider (first in chain).
    /// Fallback providers in priority order.
    /// Named routes for hint-based selection.
    /// Metrics: total embed calls.

/// Build the default auto fallback chain from config.
/// Chain order: openai → gemini → voyage → ollama → none
/// Only providers with valid api_key (or local like ollama) are included.
    // If provider is not "auto", just create the single provider

    // Build auto chain: try to create primary as openai, fallback to noop
    var chain: std.ArrayListUnmanaged(EmbeddingProvider) = .empty;

    // Determine primary from fallback_name or default to openai
    const effective_primary = fallback_name orelse "openai";
    const primary = try embeddings.createEmbeddingProvider(allocator, effective_primary, api_key, model, dims);

    // Add noop as final fallback (always available)
    const noop_inst = try allocator.create(embeddings.NoopEmbedding);

    var router = try ProviderRouter.init(allocator, primary, chain.items, &.{

// ── Tests ─────────────────────────────────────────────────────────

test "extractHint returns hint portion" {
    const hint = ProviderRouter.extractHint("hint:semantic");

test "extractHint returns null for non-hint" {
    const hint = ProviderRouter.extractHint("text-embedding-3-small");

test "extractHint empty after prefix" {
    const hint = ProviderRouter.extractHint("hint:");

test "classifyError maps EmbeddingApiError to transient" {
    const class = classifyError(error.EmbeddingApiError);

test "classifyError maps InvalidEmbeddingResponse to permanent" {
    const class = classifyError(error.InvalidEmbeddingResponse);

test "classifyError maps OutOfMemory to permanent" {
    const class = classifyError(error.OutOfMemory);

test "ProviderRouter init and deinit with noop primary" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const noop2 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();



test "ProviderRouter embed succeeds with primary noop" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();

    const vec = try p.embed(std.testing.allocator, "hello");

test "ProviderRouter embed empty text" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();

    const vec = try p.embed(std.testing.allocator, "");

    // Metrics should show primary_successes incremented

test "ProviderRouter resolveRoute finds matching route" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);



    const route = router.resolveRoute("semantic");

test "ProviderRouter resolveRoute returns null for unknown hint" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);



    const route = router.resolveRoute("offline");

test "ProviderRouter metrics tracking" {
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();

    // Make 3 calls
        const vec = try p.embed(std.testing.allocator, "test");


test "buildAutoChain non-auto returns single provider" {
    const p = try buildAutoChain(std.testing.allocator, "none", null, "", 0, null);

test "buildAutoChain auto creates router with fallback" {
    const p = try buildAutoChain(std.testing.allocator, "auto", null, "", 0, null);

// ── R3 tests ──────────────────────────────────────────────────────

/// Test helper: embedding provider that always fails.
const FailingTestProvider = struct {

test "primary available routes to primary" {
    // Create a working primary (noop) and verify it's used
    const noop1 = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();

    // Embed should succeed via primary
    const vec = try p.embed(std.testing.allocator, "test text");

    // Metrics should show primary success, no fallback

test "primary down falls back to secondary" {
    // Primary: always fails. Fallback: noop (always succeeds).
    const failing = try std.testing.allocator.create(FailingTestProvider);

    const noop_fb = try std.testing.allocator.create(embeddings.NoopEmbedding);

    const p = router.provider();

    // Embed should succeed via fallback
    const vec = try p.embed(std.testing.allocator, "test text");

    // Metrics: primary failed, fallback succeeded

test "all providers fail returns error" {
    // Both primary and fallback fail
    const failing1 = try std.testing.allocator.create(FailingTestProvider);

    const failing2 = try std.testing.allocator.create(FailingTestProvider);

    const p = router.provider();

    // Embed should fail
    const result = p.embed(std.testing.allocator, "test text");

    // Metrics: total_failures incremented
