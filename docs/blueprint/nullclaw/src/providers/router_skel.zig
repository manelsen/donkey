const std = @import("std");
const root = @import("root.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;

/// A single route: maps a task hint to a provider + model combo.
pub const Route = struct {

/// Multi-model router -- routes requests to different provider+model combos
/// based on a task hint encoded in the model parameter.
///
/// The model parameter can be:
/// - A regular model name (e.g. "anthropic/claude-sonnet-4") -> uses default provider
/// - A hint-prefixed string (e.g. "hint:reasoning") -> resolves via route table
///
/// This wraps multiple pre-created providers and selects the right one per request.
pub const RouterProvider = struct {
    /// Resolved routes: hint -> (provider_index, model).
    /// Provider name -> index lookup for explicit provider/model refs.
    /// Provider vtable interfaces (matching indexes in provider_names).
    /// Provider names (matching indexes).
    /// Create a new router.
    ///
    /// `provider_names` is a list of provider names (first is default).
    /// `providers` is a list of Provider vtable interfaces (same order as names).
    /// `routes` maps hint names to Route structs.

// ════════════════════════════════════════════════════════════════════════════
// Mock provider for tests
// ════════════════════════════════════════════════════════════════════════════

const MockProvider = struct {

fn initRouterForAllocationTest(allocator: std.mem.Allocator) !void

// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "RouterProvider init frees partial allocations on out-of-memory" {

test "resolve preserves model for non-hints" {
    const provider_names = [_][]const u8{

test "resolve strips hint prefix" {
    const provider_names = [_][]const u8{

test "unknown hint falls back to default" {
    const provider_names = [_][]const u8{

test "non-hint model uses default provider" {
    const provider_names = [_][]const u8{

test "explicit provider ref resolves provider prefix" {
    const provider_names = [_][]const u8{

test "skips routes with unknown provider" {
    const provider_names = [_][]const u8{

test "multiple routes resolve correctly" {
    const provider_names = [_][]const u8{

test "empty providers list creates router" {
    const provider_names = [_][]const u8{

// ════════════════════════════════════════════════════════════════════════════
// Provider vtable tests
// ════════════════════════════════════════════════════════════════════════════

test "vtable getName returns router" {
    const provider_names = [_][]const u8{

test "vtable chatWithSystem delegates to correct provider" {
    const provider_names = [_][]const u8{

test "vtable chatWithSystem uses default for non-hint" {
    const provider_names = [_][]const u8{

test "vtable chat delegates with hint routing" {
    const provider_names = [_][]const u8{

test "vtable chatWithTools updates request model for routed provider" {
    const provider_names = [_][]const u8{

test "vtable supportsNativeTools delegates to default" {
    const provider_names = [_][]const u8{

test "vtable supportsNativeTools false when default does not support" {
    const provider_names = [_][]const u8{

test "vtable supportsNativeTools false when no providers" {
    const prov = router.provider();


test "vtable supportsNativeTools follows default model route" {
    const provider_names = [_][]const u8{

test "vtable supportsVisionForModel follows hint routing" {
    const provider_names = [_][]const u8{

test "vtable supportsVision uses default model resolution" {
    const provider_names = [_][]const u8{

test "vtable supportsStreaming follows default model route" {
    const provider_names = [_][]const u8{

test "vtable streamChat delegates using explicit provider ref" {
    const provider_names = [_][]const u8{

test "vtable warmup warms all providers" {
    const provider_names = [_][]const u8{

test "vtable chatWithSystem returns error with no providers" {
    const prov = router.provider();

    const result = prov.chatWithSystem(std.testing.allocator, null, "hello", "model", 0.5);

test "vtable chat returns error with no providers" {
    const prov = router.provider();

    const msgs = [_]root.ChatMessage{
