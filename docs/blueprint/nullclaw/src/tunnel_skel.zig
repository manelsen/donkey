const std = @import("std");

// Tunnel -- ngrok/cloudflare/tailscale/custom tunnel management.
//
// Mirrors ZeroClaw's tunnel module: provider abstraction, factory,
// vtable interface, and per-provider implementations with real process spawning.

// ── Tunnel Provider ─────────────────────────────────────────────

pub const TunnelProvider = enum {

// ── Tunnel Config (extended) ────────────────────────────────────

pub const CloudflareTunnelConfig = struct {

pub const TailscaleTunnelConfig = struct {

pub const NgrokTunnelConfig = struct {

pub const CustomTunnelConfig = struct {

pub const TunnelFullConfig = struct {

// ── Tunnel State ────────────────────────────────────────────────

pub const TunnelState = enum {

// ── Tunnel Vtable Interface ─────────────────────────────────────

/// Tunnel vtable interface -- abstracts tunnel provider differences.
pub const TunnelAdapter = struct {

// ── NoneTunnel ──────────────────────────────────────────────────

/// No-op tunnel -- direct local access, no external exposure.
pub const NoneTunnel = struct {

// ── URL extraction helper ───────────────────────────────────────

/// Scan output text for a "https://" URL and return the slice.
fn extractUrl(output: []const u8) ?[]const u8

const URL_READ_BUFFER_BYTES: usize = 64 * 1024;
const URL_READ_TIMEOUT_DEFAULT_NS: u64 = 30 * std.time.ns_per_s;
const URL_READ_TIMEOUT_CUSTOM_NS: u64 = 90 * std.time.ns_per_s;
const URL_READ_POLL_STEP_NS: u64 = 200 * std.time.ns_per_ms;

fn tryReadUrlFromPipe(allocator: std.mem.Allocator, pipe: std.fs.File, timeout_ns: u64) ?[]const u8

fn detachChildArgv(child: *std.process.Child) void

fn cleanupFailedStart(child: *?std.process.Child, state: *TunnelState) void

// ── CloudflareTunnel ────────────────────────────────────────────

/// Cloudflare Tunnel -- wraps the `cloudflared` binary.
/// Start: `cloudflared tunnel --no-autoupdate run --url http://localhost:PORT`
/// Parses "https://" URL from stderr output.
pub const CloudflareTunnel = struct {

// ── NgrokTunnel ─────────────────────────────────────────────────

/// ngrok Tunnel -- wraps the `ngrok` binary.
/// Start: `ngrok http PORT --log stdout --log-format logfmt`
/// Then GET localhost:4040/api/tunnels to extract public URL.
pub const NgrokTunnel = struct {

// ── TailscaleTunnel ─────────────────────────────────────────────

/// Tailscale Tunnel -- uses `tailscale serve` or `tailscale funnel`.
/// Funnel mode exposes to public internet; serve is tailnet-only.
pub const TailscaleTunnel = struct {

// ── CustomTunnel ────────────────────────────────────────────────

/// Custom Tunnel -- bring your own tunnel binary.
/// Runs user-provided start_command with {port} placeholder.
/// Expects URL on first stdout line (or via url_pattern match).
pub const CustomTunnel = struct {

// ── Tunnel Instance (backward compat) ───────────────────────────

pub const Tunnel = struct {
    // Provider-specific config stored as tagged union
    /// Human-readable provider name.

// ── Factory ─────────────────────────────────────────────────────


/// Create a tunnel from config. Returns null for provider "none".
pub fn createTunnel(cfg: TunnelFullConfig) CreateTunnelError!?Tunnel

// ── Convenience constructors ────────────────────────────────────

pub fn noneTunnel() Tunnel

pub fn cloudflareTunnel(token: []const u8) Tunnel

pub fn tailscaleTunnel(funnel: bool, hostname: ?[]const u8) Tunnel

pub fn ngrokTunnel(auth_token: []const u8, domain: ?[]const u8) Tunnel

pub fn customTunnel(start_command: []const u8, health_url: ?[]const u8, url_pattern: ?[]const u8) Tunnel

// ── Tests ───────────────────────────────────────────────────────

test "TunnelProvider.fromString unknown returns null" {

test "TunnelProvider.name" {

test "factory none returns null" {
    const t = try createTunnel(.{

test "factory empty string returns null" {
    const t = try createTunnel(.{

test "factory unknown provider errors" {
    const result = createTunnel(.{

test "factory cloudflare missing config errors" {
    const result = createTunnel(.{

test "factory cloudflare with config ok" {

test "factory tailscale defaults ok" {
    const t = try createTunnel(.{

test "factory ngrok missing config errors" {
    const result = createTunnel(.{

test "factory ngrok with config ok" {

test "factory custom missing config errors" {
    const result = createTunnel(.{

test "factory custom with config ok" {

test "tailscaleTunnel funnel mode" {
    const t = tailscaleTunnel(true, "myhost");

test "ngrokTunnel with domain" {
    const t = ngrokTunnel("tok", "my.ngrok.io");

test "tunnel stop clears state" {
    var t = cloudflareTunnel("tok");
    // Don't set public_url to a literal -- stop() would try to free it if allocator is set.
    // Just test state transitions.

test "TunnelState values" {

test "TunnelFullConfig defaults" {
    const cfg = TunnelFullConfig{

test "extractUrl finds https url in output" {
    const output = "some log line\nhttps://abc123.trycloudflare.com connected\nmore output";
    const url = extractUrl(output);

test "extractUrl returns null for no url" {
    const output = "no urls here\njust some log output";

test "extractUrl ignores bare https://" {
    const output = "https:// \nnothing";

test "tryReadUrlFromPipe extracts URL from stream" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    var tmp = std.testing.tmpDir(.{

// ── TunnelAdapter vtable tests ──────────────────────────────────

test "NoneTunnel adapter name" {
    var t = NoneTunnel{

test "NoneTunnel adapter start and stop" {
    var t = NoneTunnel{

test "NoneTunnel adapter public url is null" {
    var t = NoneTunnel{

test "CloudflareTunnel adapter name" {
    var t = CloudflareTunnel.create(std.testing.allocator, "cf-token");
    const a = t.adapter();

test "CloudflareTunnel adapter not running before start" {
    var t = CloudflareTunnel.create(std.testing.allocator, "cf-token");
    const a = t.adapter();

test "CloudflareTunnel adapter stop" {
    var t = CloudflareTunnel.create(std.testing.allocator, "cf-token");
    const a = t.adapter();

test "NgrokTunnel adapter name" {
    var t = NgrokTunnel.create(std.testing.allocator, "ngrok-tok", null);
    const a = t.adapter();

test "NgrokTunnel adapter with domain" {
    var t = NgrokTunnel.create(std.testing.allocator, "tok", "my.ngrok.io");
    const a = t.adapter();

test "TailscaleTunnel adapter name" {
    var t = TailscaleTunnel.create(std.testing.allocator, false, null);
    const a = t.adapter();

test "TailscaleTunnel adapter funnel mode" {
    var t = TailscaleTunnel.create(std.testing.allocator, true, "myhost.ts.net");
    const a = t.adapter();

test "CustomTunnel adapter name" {
    var t = CustomTunnel.create(std.testing.allocator, "bore local{

test "CustomTunnel adapter empty command fails" {
    var t = CustomTunnel.create(std.testing.allocator, "   ", null, null);
    const a = t.adapter();

test "CustomTunnel adapter stop" {
    var t = CustomTunnel.create(std.testing.allocator, "echo test", null, null);
    const a = t.adapter();
