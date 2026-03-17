const std = @import("std");

/// Runtime adapter interface -- abstracts platform differences.
/// Mirrors ZeroClaw's RuntimeAdapter trait.
pub const RuntimeAdapter = struct {

// ── NativeRuntime ────────────────────────────────────────────────────

/// Native runtime -- full access, runs on Mac/Linux/Docker/Raspberry Pi.
pub const NativeRuntime = struct {

// ── DockerRuntime ────────────────────────────────────────────────────

/// Docker runtime -- container-isolated execution.
pub const DockerRuntime = struct {

// ── WasmRuntime ─────────────────────────────────────────────────────

/// Result of executing a WASM module.
pub const WasmExecutionResult = struct {

/// Capabilities granted to a WASM module.
pub const WasmCapabilities = struct {

/// WASM runtime configuration.
pub const WasmRuntimeConfig = struct {

/// WASM sandbox runtime -- executes tool modules via `wasmtime run`.
/// Provides fuel-limited, memory-capped isolation without Docker.
pub const WasmRuntime = struct {

// ── CloudflareRuntime ────────────────────────────────────────────────

/// Cloudflare Workers runtime descriptor — serverless V8 isolate environment.
/// No shell or filesystem access; 128 MB memory cap; short-lived invocations.
/// Storage is provided via Cloudflare KV/D1, not a local path.
pub const CloudflareRuntime = struct {

/// Factory: create the right runtime from a kind string.
pub fn createRuntime(kind: []const u8) !RuntimeKind

pub const RuntimeKind = enum {

// ── Tests ────────────────────────────────────────────────────────────

test "NativeRuntime name" {
    var native = NativeRuntime{

test "NativeRuntime has shell access" {
    var native = NativeRuntime{

test "NativeRuntime has filesystem access" {
    var native = NativeRuntime{

test "NativeRuntime supports long running" {
    var native = NativeRuntime{

test "NativeRuntime memory budget unlimited" {
    var native = NativeRuntime{

test "NativeRuntime storage path contains nullclaw" {
    var native = NativeRuntime{

test "DockerRuntime name" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "DockerRuntime memory budget" {
    var docker = DockerRuntime.init("alpine:3.20", "none", 256, false);
    const rt = docker.adapter();

test "DockerRuntime memory budget none" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "DockerRuntime shell access" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "DockerRuntime filesystem with mount" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, true);
    const rt = docker.adapter();

test "DockerRuntime filesystem without mount" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "DockerRuntime does not support long running" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "createRuntime native" {
    const kind = try createRuntime("native");

test "createRuntime docker" {
    const kind = try createRuntime("docker");

test "createRuntime wasm" {
    const kind = try createRuntime("wasm");

test "createRuntime cloudflare" {
    const kind = try createRuntime("cloudflare");

test "CloudflareRuntime name" {
    var cf = CloudflareRuntime{

test "CloudflareRuntime has no shell or filesystem" {
    var cf = CloudflareRuntime{

test "CloudflareRuntime memory budget 128 MB" {
    var cf = CloudflareRuntime{

test "createRuntime unknown" {

test "createRuntime empty" {

// ── Additional runtime tests ─────────────────────────────────────

test "createRuntime whitespace-only" {

test "createRuntime tab whitespace" {

test "NativeRuntime storage path" {
    var native = NativeRuntime{

test "NativeRuntime memory budget is zero (unlimited)" {
    var native = NativeRuntime{

test "DockerRuntime init stores all fields" {
    var docker = DockerRuntime.init("ubuntu:24.04", "bridge", 512, true);
    const rt = docker.adapter();

test "DockerRuntime different images" {
    var d1 = DockerRuntime.init("alpine:3.20", "none", null, false);
    var d2 = DockerRuntime.init("ubuntu:24.04", "host", 1024, true);
    const rt1 = d1.adapter();
    const rt2 = d2.adapter();

    // Both report as "docker" runtime

    // Different filesystem access

    // Different memory budgets

test "DockerRuntime storage path with workspace mount" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, true);
    const rt = docker.adapter();

test "DockerRuntime storage path without workspace mount" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "DockerRuntime does not support long running with mount" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, true);
    const rt = docker.adapter();

test "DockerRuntime has shell access" {
    var docker = DockerRuntime.init("alpine:3.20", "none", null, false);
    const rt = docker.adapter();

test "RuntimeAdapter vtable dispatch for NativeRuntime" {
    var native = NativeRuntime{

test "RuntimeAdapter vtable dispatch for DockerRuntime" {
    var docker = DockerRuntime.init("test:latest", "none", 64, true);
    const rt = docker.adapter();
    // Verify all vtable methods work via the adapter interface

test "DockerRuntime memory budget with large value" {
    var docker = DockerRuntime.init("alpine:3.20", "none", 4096, false);
    const rt = docker.adapter();

test "DockerRuntime memory budget saturating mul" {
    // Test with a very large value to ensure no overflow
    var docker = DockerRuntime.init("alpine:3.20", "none", std.math.maxInt(u64), false);
    const rt = docker.adapter();
    // Should use saturating mul, result should be maxInt(u64)

test "createRuntime case sensitive" {
    // Only exact matches should work

test "NativeRuntime full capabilities" {
    var native = NativeRuntime{

test "RuntimeKind enum values" {
    const n: RuntimeKind = .native;
    const d: RuntimeKind = .docker;
    const w: RuntimeKind = .wasm;

// ── WASM Runtime tests ──────────────────────────────────────────────

test "WasmRuntime name" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime no shell access" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime no filesystem by default" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime filesystem when read enabled" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime filesystem when write enabled" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime no long running" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime memory budget" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime memory budget custom" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime storage path" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime validate rejects zero memory" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime validate rejects excessive memory" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime validate rejects empty tools dir" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime validate rejects path traversal" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime validate accepts valid config" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime validate accepts max memory" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime effective fuel uses config default" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime effective fuel respects override" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime effective memory uses config default" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime effective memory respects override" {
    const wasm = WasmRuntime.init(.{

test "WasmRuntime default capabilities match config" {
    const wasm = WasmRuntime.init(.{

test "WasmCapabilities defaults are locked down" {
    const caps = WasmCapabilities{

test "WasmExecutionResult fields" {

test "WasmRuntimeConfig defaults" {
    const cfg = WasmRuntimeConfig{

test "WasmRuntime memory budget saturating" {
    var wasm = WasmRuntime.init(.{

test "WasmRuntime vtable dispatch" {
    var wasm = WasmRuntime.init(.{
