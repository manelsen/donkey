const std = @import("std");
const Sandbox = @import("sandbox.zig").Sandbox;

/// Maximum supported workspace path length for the mount argument buffer.
const MAX_WORKSPACE_LEN = 2048;

/// Docker sandbox backend.
/// Wraps commands with `docker run` for container isolation.
/// The workspace directory is bind-mounted into the container at the same path.
pub const DockerSandbox = struct {
    /// Pre-built "workspace_dir:workspace_dir" string for the -v flag.
    /// Stored inline to avoid allocation in wrapCommand.

pub fn createDockerSandbox(allocator: std.mem.Allocator, workspace_dir: []const u8, image: ?[]const u8) DockerSandbox

// ── Workspace Mount Validation ─────────────────────────────────────────

/// Result of validating a workspace mount path for Docker container use.
pub const ValidationResult = enum {
    /// Path is safe to use as a workspace mount
    /// Path is empty
    /// Path is not absolute (does not start with `/`)
    /// Path is the filesystem root `/`
    /// Path contains `..` traversal components
    /// Path targets a dangerous system mount point
    /// Path contains null bytes
    /// Path is not under any of the allowed workspace roots

/// System directories that must never be mounted as Docker workspaces.
/// These are bare mount points — `/etc` is blocked but `/etc/myapp` is also blocked
/// because it starts with a dangerous prefix.

/// Validate a path for use as a Docker workspace mount.
///
/// Checks performed (in order):
/// 1. Path must not be empty
/// 2. Path must not contain null bytes
/// 3. Path must be absolute (starts with `/`)
/// 4. Path must not be the root directory `/`
/// 5. Path must not contain `..` traversal components
/// 6. Path must not target dangerous system directories
/// 7. Bare `/home` is rejected (but `/home/user/...` is allowed)
///
/// If `allowed_roots` is provided (non-null, non-empty), the path must also
/// be under one of those roots.
pub fn validateWorkspaceMount(path: []const u8, allowed_roots: ?[]const []const u8) ValidationResult

/// Check if path contains ".." as a path component.
fn containsTraversal(path: []const u8) bool

/// Check if the trimmed path is a dangerous system mount or under one.
fn isDangerousMount(trimmed: []const u8) bool

/// Check if `path` is equal to or under `root`.
fn isUnderRoot(path: []const u8, root: []const u8) bool

// ── Tests ──────────────────────────────────────────────────────────────

test "docker sandbox name" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", null);
    const sb = dk.sandbox();

test "docker sandbox isAvailable returns bool" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", null);
    const sb = dk.sandbox();
    // isAvailable now checks for real docker binary; result depends on environment

test "docker sandbox wrap command prepends docker run" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", null);
    const sb = dk.sandbox();

    const argv = [_][]const u8{

test "docker sandbox wrap with custom image" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", "ubuntu:22.04");
    const sb = dk.sandbox();

    const argv = [_][]const u8{

test "docker sandbox wrap empty argv" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", null);
    const sb = dk.sandbox();

    const argv = [_][]const u8{

test "docker buffer too small returns error" {
    var dk = createDockerSandbox(std.testing.allocator, "/tmp/workspace", null);
    const sb = dk.sandbox();

    const argv = [_][]const u8{

test "docker sandbox workspace is mounted correctly" {
    var dk = createDockerSandbox(std.testing.allocator, "/home/user/myproject", null);
    const sb = dk.sandbox();

    const argv = [_][]const u8{

// ── Workspace Mount Validation Tests ───────────────────────────────────

test "mount validation: valid path /home/user/project" {
    const result = validateWorkspaceMount("/home/user/project", null);

test "mount validation: valid path /opt/workspace" {
    const result = validateWorkspaceMount("/opt/workspace", null);

test "mount validation: root path rejected" {
    // Multiple slashes still treated as root

test "mount validation: relative path rejected" {

test "mount validation: path with traversal rejected" {

test "mount validation: /etc rejected" {

test "mount validation: /usr rejected" {

test "mount validation: /bin rejected" {

test "mount validation: bare /home rejected but /home/user allowed" {

test "mount validation: /var rejected including subdirectories" {

test "mount validation: empty path rejected" {
    const result = validateWorkspaceMount("", null);

test "mount validation: path with null bytes rejected" {
    const result = validateWorkspaceMount("/home/user\x00/project", null);

test "mount validation: allowed roots enforcement" {
    const roots = [_][]const u8{

test "mount validation: ValidationResult.toString returns descriptive strings" {
