//! SSRF protection utilities.
//!
//! Extracted from `src/tools/http_request.zig` to be shared across modules.
//! Provides host extraction, localhost detection, and allowlist matching.

const std = @import("std");

/// Extract the hostname from an HTTP(S) URL, stripping port, path, query, fragment.
pub fn extractHost(url: []const u8) ?[]const u8

/// Check if a host matches the allowlist.
/// Supports exact match and wildcard subdomain patterns ("*.example.com").
pub fn hostMatchesAllowlist(host: []const u8, allowed: []const []const u8) bool

/// SSRF: check if host is localhost or a private/reserved IP.
pub fn isLocalHost(host: []const u8) bool


/// Resolve host and return a concrete connect target (IP literal) that is
/// guaranteed to be globally routable. If any resolved address is local/private,
/// reject to prevent mixed-record SSRF bypasses.
    const bare = stripHostBrackets(host);
    const unscoped = stripIpv6ZoneId(bare);

    // Fast-path literal hosts before DNS resolution to avoid platform-specific
    // resolver differences for numeric aliases (e.g. 2130706433 on Windows).


    var saw_addr = false;
    var selected_v4: ?[4]u8 = null;
    var selected_v6: ?[16]u8 = null;

                const octets: *const [4]u8 = @ptrCast(&addr.in.sa.addr);
                const bytes = addr.in6.sa.addr;





/// Resolve hostname and reject if any resolved IP is local/private/reserved.
/// This closes SSRF bypasses via numeric host aliases (e.g. 2130706433) and
/// DNS rebinding-style domains that resolve to loopback/private addresses.
pub fn hostResolvesToLocal(allocator: std.mem.Allocator, host: []const u8, port: u16) bool

pub fn stripHostBrackets(host: []const u8) []const u8

fn stripIpv6ZoneId(host: []const u8) []const u8

/// Returns true if the IPv4 address is not globally routable.
fn isNonGlobalV4(addr: [4]u8) bool

/// Returns true if the IPv6 address is not globally routable.
fn isNonGlobalV6(segs: [8]u16) bool

/// Parse a dotted-decimal IPv4 address string into 4 octets.
fn parseIpv4(s: []const u8) ?[4]u8

/// Parse single-integer IPv4 aliases into octets.
/// Supports decimal and 0x-prefixed hex notation.
fn parseIpv4IntegerAlias(s: []const u8) ?[4]u8

/// Parse an IPv6 address string into 8 segments.
/// Supports :: abbreviation and mixed IPv4 notation (::ffff:1.2.3.4).
fn parseIpv6(s: []const u8) ?[8]u16

/// Parse colon-separated hex groups into segments array starting at offset.
/// Returns number of segments parsed, or null on error.
fn parseIpv6Groups(s: []const u8, segs: []u16, start_idx: usize) ?usize

// ── Tests ───────────────────────────────────────────────────────────

test "extractHost basic" {

test "extractHost with port" {

test "extractHost strips userinfo safely" {

test "extractHost handles bracketed ipv6" {

test "extractHost parses unbracketed ipv6 authority with port" {

test "extractHost rejects invalid bracketed authority" {

test "extractHost rejects percent-encoded host bypass" {
    // %31%32%37%2e%30%2e%30%2e%31 = 127.0.0.1
    // %6c%6f%63%61%6c%68%6f%73%74 = localhost

test "extractHost returns null for non-http scheme" {

test "extractHost returns null for empty host" {

test "extractHost handles query and fragment" {

test "stripHostBrackets removes surrounding brackets only" {

test "isLocalHost detects localhost" {

test "isLocalHost detects private ranges" {

test "isLocalHost allows public" {

test "isLocalHost detects bracketed IPv6" {

test "isLocalHost detects 172.16-31 range" {

test "isLocalHost detects 127.x.x.x range" {

test "isLocalHost detects .local TLD" {

test "isNonGlobalV4 blocks 169.254.x.x link-local" {

test "isNonGlobalV4 blocks 100.64.0.1 shared address space" {

test "isNonGlobalV4 blocks multicast" {

test "isNonGlobalV4 allows public" {

test "isNonGlobalV4 blocks broadcast" {

test "isNonGlobalV4 blocks documentation ranges" {

test "isNonGlobalV4 blocks benchmarking range" {

test "isNonGlobalV6 blocks loopback" {

test "isNonGlobalV6 blocks unique local" {

test "isNonGlobalV6 blocks link-local" {

test "isNonGlobalV6 blocks documentation" {

test "isNonGlobalV6 blocks unspecified" {

test "isNonGlobalV6 blocks multicast" {

test "isNonGlobalV6 blocks IPv4-mapped private" {

test "isNonGlobalV6 allows public" {

test "isLocalHost blocks IPv6 loopback" {

test "isLocalHost blocks IPv6 unique-local" {

test "isLocalHost blocks IPv6 link-local" {

test "isLocalHost blocks IPv6 with zone id suffix" {

test "isLocalHost blocks IPv6 documentation" {

test "isLocalHost blocks IPv6 multicast" {

test "hostMatchesAllowlist exact match works" {
    const domains = [_][]const u8{

test "hostMatchesAllowlist wildcard subdomain match works" {
    const domains = [_][]const u8{

test "hostMatchesAllowlist wildcard does not match wrong domain" {
    const domains = [_][]const u8{

test "hostMatchesAllowlist empty allowlist allows all" {
    const empty: []const []const u8 = &.{

test "hostMatchesAllowlist exact entry does not implicitly match subdomains" {
    const domains = [_][]const u8{

test "parseIpv4 basic" {
    const octets = parseIpv4("192.168.1.1").?;

test "parseIpv4 rejects invalid" {

test "parseIpv4IntegerAlias parses decimal and hex" {
    const dec = parseIpv4IntegerAlias("2130706433").?;

    const hex = parseIpv4IntegerAlias("0x7f000001").?;

test "parseIpv4IntegerAlias rejects invalid" {

test "parseIpv6 loopback" {
    const segs = parseIpv6("::1").?;

test "parseIpv6 link-local" {
    const segs = parseIpv6("fe80::1").?;

test "parseIpv6 unique-local" {
    const segs = parseIpv6("fd00::1").?;

test "parseIpv6 full address" {
    const segs = parseIpv6("2607:f8b0:4004:0800:0000:0000:0000:200e").?;

test "URL extraction works correctly" {

test "hostResolvesToLocal blocks decimal and hex loopback aliases" {

test "resolveConnectHost rejects loopback aliases" {

test "hostResolvesToLocal fails closed on resolution error" {

test "resolveConnectHost fails on unresolvable host" {

test "resolveConnectHost returns literal for global ipv4" {
    const resolved = try resolveConnectHost(std.testing.allocator, "8.8.8.8", 443);
