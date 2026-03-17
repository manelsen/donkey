const std = @import("std");
const root = @import("root.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;

/// Check if an error message indicates a non-retryable client error (4xx except 429/408).
pub fn isNonRetryable(err_msg: []const u8) bool

/// Check if an error message indicates context window exhaustion.
pub fn isContextExhausted(err_msg: []const u8) bool

/// Check if an error message indicates a rate-limit (429) error.
pub fn isRateLimited(err_msg: []const u8) bool

/// Try to extract a Retry-After value (in milliseconds) from an error message.
pub fn parseRetryAfterMs(err_msg: []const u8) ?u64

/// A named provider entry for the fallback chain.
pub const ProviderEntry = struct {

/// A model fallback mapping: when `model` fails, try `fallbacks` in order.
pub const ModelFallbackEntry = struct {

const ResolvedProviderTarget = struct {

/// Provider wrapper with retry, multi-provider fallback, and model failover.
///
/// Wraps a primary inner provider and optional extra providers as a fallback chain.
/// Retries on transient errors with exponential backoff. Skips retries for
/// non-retryable client errors (4xx except 429/408). On rate-limit errors,
/// rotates API keys if available. Supports per-model fallback chains.
pub const ReliableProvider = struct {
    /// The wrapped primary inner provider to delegate calls to.
    /// Additional fallback providers (empty by default for backward compat).
    /// Per-model fallback chains.
    /// List of provider names (for diagnostics/logging).
    /// Extra API keys for rotation on rate-limit errors.
    /// Last error message from failed attempt (for retry-after parsing).

/// Returns true if any message in the request has image content_parts
/// (image_url or image_base64), indicating vision capability is required.
fn hasImageParts(request: ChatRequest) bool

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "isContextExhausted detects common patterns" {

test "isNonRetryable detects common patterns" {

test "isRateLimited detection" {

test "parseRetryAfterMs integer" {

test "parseRetryAfterMs float" {

test "parseRetryAfterMs missing" {

test "ReliableProvider computeBackoff uses retry-after" {
    const prov = ReliableProvider.init(&.{

test "ReliableProvider computeBackoff caps at 30s" {
    const prov = ReliableProvider.init(&.{

test "ReliableProvider computeBackoff falls back to base" {
    const prov = ReliableProvider.init(&.{

test "ReliableProvider auth rotation cycles keys" {
    const keys = [_][]const u8{

test "ReliableProvider auth rotation returns null when empty" {
    var prov = ReliableProvider.init(&.{

test "isNonRetryable embedded in longer message" {

test "isRateLimited requires both 429 and keyword" {
    // Just "429" alone without rate/limit/Too Many should be false
    // With proper keywords

test "isRateLimited empty string" {

test "parseRetryAfterMs with underscore separator" {

test "parseRetryAfterMs with space separator" {

test "parseRetryAfterMs zero value" {

test "parseRetryAfterMs case insensitive" {

test "parseRetryAfterMs ignores non-numeric" {

test "ReliableProvider init enforces min backoff 50ms" {
    const prov = ReliableProvider.init(&.{

test "ReliableProvider computeBackoff uses base when retry-after is smaller" {
    const prov = ReliableProvider.init(&.{

// ════════════════════════════════════════════════════════════════════════════
// Mock provider for vtable retry tests
// ════════════════════════════════════════════════════════════════════════════

const MockInnerProvider = struct {

/// Mock that records which model was used for each call.
const ModelAwareMock = struct {

const VisionByModelMock = struct {

test "ReliableProvider vtable succeeds without retry" {
    var mock = MockInnerProvider{

test "ReliableProvider vtable retries then recovers" {
    var mock = MockInnerProvider{

test "ReliableProvider vtable exhausts retries and returns error" {
    var mock = MockInnerProvider{

test "ReliableProvider records fallback detail for non-classified errors" {

    var reliable = ReliableProvider.initWithProvider(mock.toProvider(), 0, 50);
    const prov = reliable.provider();

    const result = prov.chatWithSystem(std.testing.allocator, null, "hello", "model", 0.5);

    const detail = (try root.snapshotLastApiErrorDetail(std.testing.allocator)).?;

test "ReliableProvider propagates context errors for recovery" {
    var reliable = ReliableProvider.initWithProvider(mock.toProvider(), 1, 50);
    const prov = reliable.provider();

    const result = prov.chatWithSystem(std.testing.allocator, null, "hello", "model", 0.5);

test "ReliableProvider vtable chat retries then recovers" {
    var mock = MockInnerProvider{

test "ReliableProvider vtable delegates supportsNativeTools" {
    var mock_yes = MockInnerProvider{

test "ReliableProvider supportsVision checks full provider chain" {

    var reliable = ReliableProvider.initWithProvider(inner.toProvider(), 0, 50).withExtras(&extras);
    const prov = reliable.provider();

test "ReliableProvider vtable delegates getName" {
    var mock = MockInnerProvider{

test "ReliableProvider vtable zero retries fails immediately" {
    var mock = MockInnerProvider{

// ════════════════════════════════════════════════════════════════════════════
// New tests: model fallback chain
// ════════════════════════════════════════════════════════════════════════════

test "modelChain with no fallbacks returns single element" {
    const reliable = ReliableProvider.init(&.{

test "modelChain with fallbacks returns full chain" {
    const reliable = ReliableProvider.init(&.{

test "modelChain with unrelated model returns single element" {
    const reliable = ReliableProvider.init(&.{

test "withModelFallbacks builder preserves other fields" {
    const reliable = ReliableProvider.init(&.{

test "withExtras builder preserves other fields" {
    var mock = MockInnerProvider{

test "warmup calls inner and extras" {
    var inner_mock = MockInnerProvider{

test "multi-provider fallback: primary fails, extra succeeds" {
    var primary = MockInnerProvider{

test "model failover tries fallback model" {
    const fail_models = [_][]const u8{

test "model failover all models fail returns error" {
    const fail_models = [_][]const u8{

test "supportsNativeTools returns true if any extra supports it" {
    var inner_mock = MockInnerProvider{

test "multi-provider chat fallback" {
    var primary = MockInnerProvider{

// ════════════════════════════════════════════════════════════════════════════
// Vision routing tests
// ════════════════════════════════════════════════════════════════════════════

test "hasImageParts returns false with no content_parts" {
    const msgs = [_]root.ChatMessage{

test "hasImageParts returns false with text-only content_parts" {
    const parts = [_]root.ContentPart{

test "hasImageParts returns true with image_url part" {
    const request = ChatRequest{

test "hasImageParts returns true with image_base64 part" {
    const request = ChatRequest{

test "chatImpl skips non-vision inner and routes image request to vision-capable extra" {
    var inner = MockInnerProvider{

test "chatImpl non-image request routes to inner even if inner lacks vision" {
    var inner = MockInnerProvider{

test "chatImpl returns ProviderDoesNotSupportVision when all providers lack vision" {
    var inner = MockInnerProvider{

test "chatImpl returns ProviderDoesNotSupportVision when vision exists only for other models" {
    var inner = VisionByModelMock{

test "streamChatImpl routes image request to vision-capable extra, skips inner" {
    var inner = MockInnerProvider{

test "streamChatImpl returns ProviderDoesNotSupportVision when all providers lack vision" {
    var inner = MockInnerProvider{
