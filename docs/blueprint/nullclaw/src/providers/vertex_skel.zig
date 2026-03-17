const std = @import("std");
const root = @import("root.zig");
const gemini = @import("gemini.zig");
const config_types = @import("../config_types.zig");
const platform = @import("../platform.zig");

const Provider = root.Provider;
const ChatRequest = root.ChatRequest;
const ChatResponse = root.ChatResponse;

const ServiceAccountCredentials = struct {

/// Authentication method for Vertex AI.
    /// Token from config models.providers.vertex.api_key.
    /// Service account JSON from config models.providers.vertex.api_key.
    /// Token from VERTEX_API_KEY env var.
    /// Service account JSON from VERTEX_API_KEY env var.
    /// Token from VERTEX_OAUTH_TOKEN env var.
    /// Token from GOOGLE_OAUTH_ACCESS_TOKEN env var.

    pub fn source(self: VertexAuth) []const u8

    /// models.providers.vertex.base_url (unowned)
    /// VERTEX_BASE_URL (owned)
    /// Built from VERTEX_PROJECT_ID + VERTEX_LOCATION (owned)

    pub fn value(self: VertexBase) []const u8

    pub fn source(self: VertexBase) []const u8

/// Vertex AI Gemini provider.
///
/// Endpoint resolution order:
/// 1. models.providers.vertex.base_url
/// 2. VERTEX_BASE_URL
/// 3. Build from VERTEX_PROJECT_ID (+ optional VERTEX_LOCATION, default: global)
/// 4. Build from service-account `project_id` (+ optional VERTEX_LOCATION, default: global)
pub const VertexProvider = struct {

const ServiceAccountAccessToken = struct {

fn jsonNonEmptyString(obj: std.json.ObjectMap, key: []const u8) ?[]const u8

fn parseExpiresIn(v: std.json.Value) ?i64

fn parseServiceAccountCredentials(allocator: std.mem.Allocator, raw: []const u8) ?ServiceAccountCredentials

fn base64UrlEncodeAlloc(allocator: std.mem.Allocator, input: []const u8) ![]u8

    var iat_buf: [32]u8 = undefined;
    const iat_str = std.fmt.bufPrint(&iat_buf, "{

    const temp_dir = try platform.getTempDir(allocator);

    const filename = try std.fmt.allocPrint(allocator, "nullclaw-vertex-sa-{

fn buildServiceAccountAssertion(allocator: std.mem.Allocator, creds: ServiceAccountCredentials) ![]u8

fn isFormUrlencodedUnreserved(c: u8) bool

    const HEX = "0123456789ABCDEF";


    const parsed = std.json.parseFromSlice(std.json.Value, allocator, response_body, .{


    const assertion = try buildServiceAccountAssertion(allocator, creds);

    var form: std.ArrayListUnmanaged(u8) = .empty;



fn trimTrailingSlash(url: []const u8) []const u8

fn normalizeModelName(model: []const u8) []const u8

pub fn buildGenerateUrl(allocator: std.mem.Allocator, base: []const u8, model: []const u8) ![]u8

pub fn buildStreamUrl(allocator: std.mem.Allocator, base: []const u8, model: []const u8) ![]u8

    var buf: std.ArrayListUnmanaged(u8) = .empty;




    var temp_buf: [16]u8 = undefined;
    const temp_str = std.fmt.bufPrint(&temp_buf, "{


    var buf: std.ArrayListUnmanaged(u8) = .empty;

    var system_prompt: ?[]const u8 = null;

    var count: usize = 0;




                        var text_buf: std.ArrayListUnmanaged(u8) = .empty;




    var temp_buf: [16]u8 = undefined;
    const temp_str = std.fmt.bufPrint(&temp_buf, "{


// ════════════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════════════

test "buildGenerateUrl normalizes model forms" {
    const alloc = std.testing.allocator;
    const base = "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models/";

    const url1 = try buildGenerateUrl(alloc, base, "gemini-2.5-pro");

    const url2 = try buildGenerateUrl(alloc, base, "models/gemini-2.5-flash");

    const url3 = try buildGenerateUrl(alloc, base, "publishers/google/models/gemini-2.0-flash");

test "buildStreamUrl appends alt=sse" {
    const alloc = std.testing.allocator;
    const base = "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models";
    const url = try buildStreamUrl(alloc, base, "gemini-2.5-pro");

test "buildDefaultBase global endpoint" {
    const alloc = std.testing.allocator;
    const base = try VertexProvider.buildDefaultBase(alloc, "proj-1", "global");

test "buildDefaultBase regional endpoint" {
    const alloc = std.testing.allocator;
    const base = try VertexProvider.buildDefaultBase(alloc, "proj-2", "us-central1");

test "provider creates with explicit token and base_url" {
    const p = VertexProvider.init(std.testing.allocator, "ya29.token", "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models");

test "buildAuthHeader uses explicit bearer token" {
    const alloc = std.testing.allocator;
    var p = VertexProvider.init(alloc, "ya29.explicit", "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models");

    const auth_header = try p.buildAuthHeader(alloc);

test "parseServiceAccountCredentials extracts required fields" {
    const alloc = std.testing.allocator;
    const creds = parseServiceAccountCredentials(alloc, raw) orelse return error.TestExpectedEqual;


test "parseServiceAccountCredentials rejects non-https token_uri" {
    const alloc = std.testing.allocator;

test "buildAuthHeader uses service-account oauth2 token exchange path" {
    const alloc = std.testing.allocator;
    var p = VertexProvider.init(alloc, raw, null);

    const auth_header = try p.buildAuthHeader(alloc);


test "resolveAuth accepts config service account json" {
    const alloc = std.testing.allocator;

    const auth = VertexProvider.resolveAuth(alloc, raw) orelse return error.TestExpectedEqual;


test "service-account project id can build default base url" {
    const alloc = std.testing.allocator;
    const auth = VertexProvider.resolveAuth(alloc, raw) orelse return error.TestExpectedEqual;

    const project_id = VertexProvider.serviceAccountProjectId(auth) orelse return error.TestExpectedEqual;
    const base = try VertexProvider.buildDefaultBase(alloc, project_id, "global");

test "provider rejects whitespace explicit token" {
    const p = VertexProvider.init(std.testing.allocator, "   ", "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models");
    const src = p.authSource();

test "provider getName returns Vertex" {
    var p = VertexProvider.init(std.testing.allocator, "ya29.token", "https://aiplatform.googleapis.com/v1/projects/p/locations/global/publishers/google/models");
    const prov = p.provider();

test "streaming support is enabled" {

test "streamChatImpl fails without credentials" {

    const prov = p.provider();
    const msgs = [_]root.ChatMessage{

test "chatWithSystem fails without endpoint base" {

    const prov = p.provider();

test "buildChatRequestBody plain text" {
    const alloc = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody honors max_tokens" {
    const alloc = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody maps reasoning_effort to thinkingLevel for gemini-3 flash" {
    const alloc = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody maps reasoning_effort to thinkingBudget for gemini-2.5" {
    const alloc = std.testing.allocator;
    const msgs = [_]root.ChatMessage{

test "buildChatRequestBody with image base64" {
    const alloc = std.testing.allocator;
    const parts = [_]root.ContentPart{

test "parse Gemini-style response via shared parser" {
    const text = try gemini.GeminiProvider.parseResponse(std.testing.allocator, body);

test "parseServiceAccountAccessTokenResponse parses token payload" {
    const alloc = std.testing.allocator;
    const payload = "{

test "deinit frees owned env allocations" {
    const alloc = std.testing.allocator;


test "deinit frees explicit service-account credentials and cached token" {
    const alloc = std.testing.allocator;

