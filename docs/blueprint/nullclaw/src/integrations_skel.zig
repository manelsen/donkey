const std = @import("std");

// Integrations -- integration registry and status tracking.
//
// Mirrors ZeroClaw's integrations module: categories, status,
// and the full catalog of supported integrations.

// ── Integration Status ──────────────────────────────────────────

pub const IntegrationStatus = enum {

// ── Integration Category ────────────────────────────────────────

pub const IntegrationCategory = enum {

// ── Integration Entry ───────────────────────────────────────────

pub const IntegrationEntry = struct {

// ── Registry ────────────────────────────────────────────────────

/// Returns the full catalog of integrations.
/// Status is resolved statically (no config dependency in Zig port).
pub fn allIntegrations() []const IntegrationEntry

    // Chat Providers
    // AI Models
    // Productivity
    // Music & Audio
    // Smart Home
    // Tools & Automation
    // Media & Creative
    // Social
    // Platforms

/// Look up an integration by name (case-insensitive).
pub fn findIntegration(name: []const u8) ?*const IntegrationEntry

/// Count integrations in a given category.
pub fn countByCategory(category: IntegrationCategory) usize

/// Count integrations with a given status.
pub fn countByStatus(status: IntegrationStatus) usize

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool

// ── Tests ───────────────────────────────────────────────────────

test "allIntegrations returns at least 50 entries" {
    const entries = allIntegrations();

test "all categories represented" {

test "no empty names or descriptions" {

test "no duplicate names" {
    const entries = allIntegrations();

test "category all includes every variant once" {
    const all = IntegrationCategory.all();

test "findIntegration finds Telegram" {
    const entry = findIntegration("Telegram");

test "findIntegration is case-insensitive" {
    const entry = findIntegration("telegram");

test "findIntegration returns null for unknown" {

test "Shell and File System are always active" {
    const shell = findIntegration("Shell");

    const fs = findIntegration("File System");

test "coming soon integrations" {
    const signal = findIntegration("Signal");

    const nostr = findIntegration("Nostr");

    const spotify = findIntegration("Spotify");

    const ha = findIntegration("Home Assistant");

test "chat category has at least 5 entries" {

test "ai_model category has at least 5 entries" {

test "countByStatus returns non-zero for available" {

test "countByStatus returns non-zero for active" {

test "countByStatus returns non-zero for coming_soon" {

test "macOS integration is active" {
    const macos = findIntegration("macOS");
