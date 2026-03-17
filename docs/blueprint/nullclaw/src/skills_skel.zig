const std = @import("std");
const zig_builtin = @import("builtin");
const fs_compat = @import("fs_compat.zig");
const platform = @import("platform.zig");
const json_miniparse = @import("json_miniparse.zig");

// Skills — user-defined capabilities loaded from disk.
//
// Each skill lives in ~/.nullclaw/workspace/skills/<name>/ with:
//   - SKILL.toml  — preferred manifest format (zeroclaw-compatible)
//   - skill.json  — legacy manifest format (optional)
//   - SKILL.md    — instruction text
//
// The skillforge module handles discovery and evaluation;
// this module handles definition, loading, installation, and removal.

// ── Types ───────────────────────────────────────────────────────

pub const Skill = struct {
    /// If true, full instructions are always included in the system prompt.
    /// If false, only an XML summary is included and the agent must use file_read to load instructions.
    /// List of CLI binaries required by this skill (e.g. "docker", "git").
    /// List of environment variables required by this skill (e.g. "OPENAI_API_KEY").
    /// Whether all requirements are satisfied. Set by checkRequirements().
    /// Human-readable description of missing dependencies. Set by checkRequirements().
    /// Path to the skill directory on disk (for file_read references).

pub const SkillManifest = struct {

// ── JSON Parsing (manual, no allocations) ───────────────────────

/// Extract a string field value from a JSON blob (minimal parser — no allocations).
/// Same pattern as tools/shell.zig parseStringField.
fn parseStringField(json: []const u8, key: []const u8) ?[]const u8

/// Extract a boolean field value from a JSON blob (true/false literal).
fn parseBoolField(json: []const u8, key: []const u8) ?bool

/// Parse a JSON string array field, returning allocated slices.
/// E.g. for `"requires_bins": ["docker", "git"]` returns &["docker", "git"].
/// Caller owns the returned outer slice and each inner slice.
fn parseStringArray(allocator: std.mem.Allocator, json: []const u8, key: []const u8) ![]const []const u8

/// Free a string array returned by parseStringArray.
fn freeStringArray(allocator: std.mem.Allocator, arr: []const []const u8) void

/// Parse a skill.json manifest from raw JSON bytes.
/// Returns slices pointing into the original json_bytes (no allocations needed
/// beyond what the caller already owns for json_bytes).
/// Note: requires_bins and requires_env are heap-allocated; caller must use allocator version.
pub fn parseManifest(json_bytes: []const u8) !SkillManifest

/// Parse a skill.json manifest with allocator support for array fields.
pub fn parseManifestAlloc(allocator: std.mem.Allocator, json_bytes: []const u8) !SkillManifest

fn stripTomlInlineComment(value: []const u8) []const u8

fn parseTomlStringLiteral(raw_value: []const u8) ?[]const u8

const TomlStringPrefix = struct {

fn parseTomlStringPrefix(raw_value: []const u8) ?TomlStringPrefix

fn parseTomlSkillField(toml_bytes: []const u8, key: []const u8) ?[]const u8

// ── Frontmatter Parsing ─────────────────────────────────────────
//
// SKILL.md files may contain YAML frontmatter — a `---`-delimited block at the
// top of the file that carries manifest metadata (name, description, version,
// author, always, requires_bins, requires_env).
//
// When a skill directory has only SKILL.md (no SKILL.toml / skill.json), the
// frontmatter is parsed to populate SkillManifest fields.  The body (content
// after the closing `---`) becomes the skill instructions.

const FrontmatterSplit = struct {
    /// Raw frontmatter text between the opening and closing `---` delimiters.
    /// Content after the closing `---` delimiter (the actual instructions).

/// Detect `---`-delimited frontmatter at the top of `content`.
/// Returns the raw meta and body slices, or null if no valid frontmatter block.
fn splitFrontmatter(content: []const u8) ?FrontmatterSplit

/// Extract a simple `key: value` string from YAML-subset frontmatter lines.
/// Handles bare values, single-quoted, and double-quoted values.
/// Returns a slice into the `meta` buffer — caller must dupe.
fn parseFrontmatterField(meta: []const u8, key: []const u8) ?[]const u8

/// Strip inline `#` comments from a YAML value, respecting quoted strings.
fn stripFrontmatterInlineComment(value: []const u8) []const u8

/// Extract a boolean field from YAML-subset frontmatter.
/// Recognizes `true`, `false`, `yes`, `no` (case-insensitive).
fn parseFrontmatterBoolField(meta: []const u8, key: []const u8) ?bool

/// Parse a YAML string array field from frontmatter.
/// Supports two formats:
///   Block sequence:  `key:\n  - item1\n  - item2`
///   Flow sequence:   `key: [item1, item2]`
/// Caller owns the returned outer slice and each inner slice.
fn parseFrontmatterStringArray(allocator: std.mem.Allocator, meta: []const u8, key: []const u8) ![]const []const u8

/// Strip surrounding quotes (single or double) from a YAML value.
fn stripYamlQuotes(val: []const u8) []const u8

/// Read a SKILL.md file and parse it (with optional YAML frontmatter) into a fully-owned Skill.
/// All string fields are heap-allocated via `allocator`; caller must free with `freeSkill`.
/// When no frontmatter name is found, the directory basename of `skill_dir_path` is used.
/// Returns `error.ManifestNotFound` if the SKILL.md file does not exist.


    const split = splitFrontmatter(content);
    const meta = if (split) |s| s.meta else "";
    const body = if (split) |s| s.body else content;

    const fm_name = parseFrontmatterField(meta, "name") orelse "";
    const dirname = std.fs.path.basename(skill_dir_path);
    const skill_name = if (fm_name.len > 0) fm_name else dirname;

    const always = parseFrontmatterBoolField(meta, "always") orelse false;

    const requires_bins = parseFrontmatterStringArray(allocator, meta, "requires_bins") catch &.{

// ── Skill Loading ───────────────────────────────────────────────

/// Load a single skill from a directory.
/// Reads SKILL.toml (preferred), then skill.json (legacy), then SKILL.md fallback.
/// If both manifests are missing but SKILL.md exists, loads a markdown-only skill using
/// the directory name as skill name (zeroclaw-compatible behavior).
pub fn loadSkill(allocator: std.mem.Allocator, skill_dir_path: []const u8) !Skill

/// Free all heap-allocated fields of a Skill.
pub fn freeSkill(allocator: std.mem.Allocator, skill: *const Skill) void

/// Free a slice of skills and all their contents.
pub fn freeSkills(allocator: std.mem.Allocator, skills_slice: []Skill) void

// ── Requirement Checking ────────────────────────────────────────

/// Check whether a skill's required binaries and env vars are available.
/// Updates skill.available and skill.missing_deps in place.
pub fn checkRequirements(allocator: std.mem.Allocator, skill: *Skill) void

/// Check if a binary exists on PATH using `which`.
fn checkBinaryExists(allocator: std.mem.Allocator, bin_name: []const u8) bool

// ── Listing ─────────────────────────────────────────────────────

/// Scan workspace_dir/skills/ for subdirectories, loading each as a Skill.
/// Returns owned slice; caller must free with freeSkills().
pub fn listSkills(allocator: std.mem.Allocator, workspace_dir: []const u8) ![]Skill

/// Load skills from two sources: built-in and workspace.
/// Workspace skills with the same name override built-in skills.
/// Also runs checkRequirements() on each loaded skill.
pub fn listSkillsMerged(allocator: std.mem.Allocator, builtin_dir: []const u8, workspace_dir: []const u8) ![]Skill

// ── Installation ────────────────────────────────────────────────

/// Detect whether source looks like a git remote URL/path.
/// Accepted:
/// - https://host/owner/repo(.git)
/// - http://host/owner/repo(.git)
/// - ssh://git@host/owner/repo(.git)
/// - git://host/owner/repo(.git)
/// - git@host:owner/repo(.git)
fn isGitSource(source: []const u8) bool

fn isGitSchemeSource(source: []const u8, scheme: []const u8) bool

fn isGitScpSource(source: []const u8) bool

fn clearInstallErrorDetail(allocator: std.mem.Allocator, detail_out: ?*?[]u8) void

fn setInstallErrorDetail(allocator: std.mem.Allocator, detail_out: ?*?[]u8, detail: []const u8) void

fn containsAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool

fn classifyGitCloneError(stderr: []const u8) anyerror

fn validateSkillName(name: []const u8) !void

const SKILL_AUDIT_MAX_FILE_BYTES: usize = 512 * 1024;

fn startsWithAsciiIgnoreCase(haystack: []const u8, needle: []const u8) bool

fn endsWithAsciiIgnoreCase(haystack: []const u8, suffix: []const u8) bool

fn findAsciiIgnoreCaseFrom(haystack: []const u8, needle: []const u8, start: usize) ?usize

fn isWordByte(c: u8) bool

fn containsWordIgnoreCase(haystack: []const u8, needle: []const u8) bool

fn hasScriptSuffix(path: []const u8) bool

fn isMarkdownFile(path: []const u8) bool

fn isTomlFile(path: []const u8) bool

fn hasShellShebang(path: []const u8) bool

fn containsPipeToShell(content: []const u8, command: []const u8) bool

fn containsNetcatExec(content: []const u8) bool

fn detectHighRiskSnippet(content: []const u8) bool

fn containsShellChaining(command: []const u8) bool

fn normalizeMarkdownTarget(raw_target: []const u8) []const u8

fn stripQueryAndFragment(target: []const u8) []const u8

fn urlScheme(target: []const u8) ?[]const u8

fn looksLikeAbsolutePath(target: []const u8) bool

fn pathWithinRoot(path: []const u8, root: []const u8) bool

fn isRegularFile(path: []const u8) bool

    const normalized = normalizeMarkdownTarget(raw_target);


    const stripped = stripQueryAndFragment(normalized);

    const source_parent = std.fs.path.dirname(source_path) orelse return error.SkillSecurityAuditFailed;
    const linked_path = try std.fmt.allocPrint(allocator, "{

    var i: usize = 0;

        var close_bracket = i + 1;

        var close_paren = close_bracket + 2;

        const raw_target = content[close_bracket + 2 .. close_paren];

const TomlToolAuditState = struct {

fn finalizeTomlToolAudit(state: *TomlToolAuditState) !void

fn auditTomlPromptsFragment(raw_fragment: []const u8) !bool

fn auditTomlPromptsValue(raw_value: []const u8) !bool

fn auditTomlContent(content: []const u8) !void


    const markdown = isMarkdownFile(file_path);
    const toml = isTomlFile(file_path);




fn pathIsSymlink(path: []const u8) !bool

fn auditSkillDirectory(allocator: std.mem.Allocator, root_dir_path: []const u8) !void

fn snapshotSkillChildren(allocator: std.mem.Allocator, skills_dir_path: []const u8) !std.StringHashMap(void)

fn freePathSnapshot(allocator: std.mem.Allocator, paths: *std.StringHashMap(void)) void

    var created: ?[]u8 = null;

    var dir = try std.fs.openDirAbsolute(skills_dir_path, .{

fn removeGitMetadata(skill_path: []const u8) !void

fn pathExists(path: []const u8) bool

fn hasSkillMarkers(allocator: std.mem.Allocator, dir_path: []const u8) !bool

fn hasInstallableSkillContent(allocator: std.mem.Allocator, dir_path: []const u8) !bool

fn isSkillMarkerBasename(base_name: []const u8) bool

fn resolveInstallableSkillSourceRoot(allocator: std.mem.Allocator, source_path: []const u8) ![]u8

const CopyDirPair = struct {

fn copyDirRecursiveSecure(allocator: std.mem.Allocator, src_root: []const u8, dst_root: []const u8) !void


    const skills_dir_path = try std.fmt.allocPrint(allocator, "{

fn deriveSkillNameFromSourcePath(allocator: std.mem.Allocator, source_path: []const u8) ![]u8

    const collection_path = try std.fmt.allocPrint(allocator, "{

    const skills_dir_path = try std.fmt.allocPrint(allocator, "{

/// Install a skill from either a local path or a git source URL, with optional error detail output.

/// Install a skill from either a local path or a git source URL.
pub fn installSkill(allocator: std.mem.Allocator, source: []const u8, workspace_dir: []const u8) !void

/// Install a skill by copying its directory into workspace_dir/skills/<source-dirname>/.
/// Destination directory naming follows zeroclaw local install behavior.
pub fn installSkillFromPath(allocator: std.mem.Allocator, source_path: []const u8, workspace_dir: []const u8) !void

/// Copy a file from src to dst. Supports both absolute and relative paths.
fn copyFilePath(src: []const u8, dst: []const u8) !void

// ── Removal ─────────────────────────────────────────────────────

/// Remove a skill by deleting its directory from workspace_dir/skills/<name>/.
pub fn removeSkill(allocator: std.mem.Allocator, name: []const u8, workspace_dir: []const u8) !void

// ── Community Skills Sync ────────────────────────────────────────

pub const OPEN_SKILLS_REPO_URL = "https://github.com/besoeasy/open-skills";
pub const COMMUNITY_SYNC_INTERVAL_DAYS: u64 = 7;

pub const CommunitySkillsSync = struct {

/// Parse integer field from minimal JSON like {"last_sync": 12345}.
fn parseIntField(json: []const u8, key: []const u8) ?i64

/// Read the last_sync timestamp from a marker file.
/// Returns null if file doesn't exist or can't be parsed.
fn readSyncMarker(marker_path: []const u8, buf: []u8) ?i64

/// Write a timestamp into the marker file, creating parent directories as needed.
fn writeSyncMarkerWithTimestamp(allocator: std.mem.Allocator, marker_path: []const u8, timestamp: i64) !void

/// Write current timestamp into the marker file.
fn writeSyncMarker(allocator: std.mem.Allocator, marker_path: []const u8) !void

/// Synchronize community skills from the open-skills repository.
/// Gracefully returns without error if git is unavailable or sync is disabled.
pub fn syncCommunitySkills(allocator: std.mem.Allocator, workspace_dir: []const u8) !void

/// Load community skills from .md files in the community directory.
/// Returns owned slice; caller must free with freeSkills().
pub fn loadCommunitySkills(allocator: std.mem.Allocator, community_dir: []const u8) ![]Skill

/// Merge community skills into workspace skills, with workspace skills taking priority.
/// Returns a new slice; caller must free with freeSkills().
/// The input slices are consumed (caller must NOT free them separately).
pub fn mergeCommunitySkills(allocator: std.mem.Allocator, workspace_skills: []Skill, community_skills: []Skill) ![]Skill

// ── Sync Result API ─────────────────────────────────────────────

pub const SyncResult = struct {

/// Count .md files in a directory (non-recursive).
fn countMdFiles(dir_path: []const u8) u32

/// Synchronize community skills and return a result struct with sync status.
/// This wraps syncCommunitySkills with additional information about the outcome.
pub fn syncCommunitySkillsResult(allocator: std.mem.Allocator, workspace_dir: []const u8) !SyncResult

/// Free a SyncResult's heap-allocated message.
pub fn freeSyncResult(allocator: std.mem.Allocator, result: *const SyncResult) void

// ── Tests ───────────────────────────────────────────────────────

fn runCommand(allocator: std.mem.Allocator, argv: []const []const u8) !void

test "parseManifest full JSON" {
    const m = try parseManifest(json);

test "parseManifest minimal JSON (name only)" {
    const m = try parseManifest(json);

test "parseManifest missing name returns error" {

test "parseManifest empty JSON object returns error" {

test "parseManifest handles whitespace in JSON" {
    const m = try parseManifest(json);

test "parseManifest handles escaped quotes" {
    const m = try parseManifest(json);

test "parseStringField basic" {
    const json = "{

test "parseStringField missing key" {
    const json = "{

test "parseStringField non-string value" {
    const json = "{

test "Skill struct defaults" {
    const s = Skill{

test "Skill struct custom values" {

test "SkillManifest fields" {

test "listSkills from nonexistent directory" {
    const allocator = std.testing.allocator;
    const skills = try listSkills(allocator, "/tmp/nullclaw-test-skills-nonexistent-dir");

test "listSkills from empty directory" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill reads manifest and instructions" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill without SKILL.md still works" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill without skill.json falls back to markdown-only skill" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill reads metadata from SKILL.toml" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill prefers SKILL.toml metadata over skill.json" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "loadSkill missing manifest returns error" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "listSkills discovers skills in subdirectories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "listSkills discovers markdown-only skill directories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "listSkills skips directories without valid manifest" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "isGitSource accepts remote protocols and scp style" {


test "isGitSource rejects local paths and invalid inputs" {


test "classifyGitCloneError maps common git clone failures" {

test "snapshotSkillChildren and detectNewlyInstalledDirectory roundtrip" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "detectNewlyInstalledDirectory errors for none and multiple directories" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects symlink entries" {
    if (comptime @import("builtin").os.tag == .windows) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory allows large non-script files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects script suffix files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects shell shebang files" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects markdown links escaping skill root" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects TOML tool command with shell chaining" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects TOML tool entries without command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects TOML shell tool with empty command" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{

test "auditSkillDirectory rejects invalid TOML manifest syntax" {
    const allocator = std.testing.allocator;
    var tmp = std.testing.tmpDir(.{