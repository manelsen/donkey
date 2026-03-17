//! Memory module — persistent knowledge storage for nullclaw.
//!
//! Mirrors ZeroClaw's memory architecture:
//!   - Memory vtable interface (store, recall, get, list, forget, count)
//!   - MemoryEntry, MemoryCategory
//!   - Multiple backends: SQLite (FTS5), Markdown (file-based), None (no-op)
//!   - ResponseCache for LLM response deduplication
//!   - Document chunking for large markdown files

const std = @import("std");
const build_options = @import("build_options");
const config_types = @import("../config_types.zig");
const provider_api_key = @import("../providers/api_key.zig");
const log = std.log.scoped(.memory);

// engines/ (Layer A: Primary Store)
pub const sqlite = if (build_options.enable_sqlite) @import("engines/sqlite.zig") else @import("engines/sqlite_disabled.zig");
pub const markdown = @import("engines/markdown.zig");
pub const none = @import("engines/none.zig");
pub const memory_lru = @import("engines/memory_lru.zig");
    pub const LucidMemory = struct {};
pub const redis = @import("engines/redis.zig");
    pub const LanceDbMemory = struct {};
pub const api = @import("engines/api.zig");
pub const clickhouse = @import("engines/clickhouse.zig");
pub const registry = @import("engines/registry.zig");

// retrieval/ (Layer B: Retrieval Engine)
pub const retrieval = @import("retrieval/engine.zig");
pub const retrieval_qmd = @import("retrieval/qmd.zig");
pub const rrf = @import("retrieval/rrf.zig");
pub const query_expansion = @import("retrieval/query_expansion.zig");
pub const temporal_decay = @import("retrieval/temporal_decay.zig");
pub const mmr = @import("retrieval/mmr.zig");
pub const adaptive = @import("retrieval/adaptive.zig");
pub const llm_reranker = @import("retrieval/llm_reranker.zig");

// vector/ (Layer C: Vector Plane)
pub const vector = @import("vector/math.zig");
pub const vector_store = @import("vector/store.zig");
pub const embeddings = @import("vector/embeddings.zig");
pub const embeddings_gemini = @import("vector/embeddings_gemini.zig");
pub const embeddings_voyage = @import("vector/embeddings_voyage.zig");
pub const embeddings_ollama = @import("vector/embeddings_ollama.zig");
pub const provider_router = @import("vector/provider_router.zig");
pub const store_qdrant = @import("vector/store_qdrant.zig");
pub const store_pgvector = @import("vector/store_pgvector.zig");
pub const circuit_breaker = @import("vector/circuit_breaker.zig");
pub const outbox = @import("vector/outbox.zig");
pub const chunker = @import("vector/chunker.zig");

// lifecycle/ (Layer D: Runtime Orchestrator)
pub const cache = @import("lifecycle/cache.zig");
pub const semantic_cache = @import("lifecycle/semantic_cache.zig");
pub const hygiene = @import("lifecycle/hygiene.zig");
pub const snapshot = @import("lifecycle/snapshot.zig");
pub const rollout = @import("lifecycle/rollout.zig");
pub const migrate = @import("lifecycle/migrate.zig");
pub const diagnostics = @import("lifecycle/diagnostics.zig");
pub const summarizer = @import("lifecycle/summarizer.zig");

pub const SqliteMemory = sqlite.SqliteMemory;
pub const MarkdownMemory = markdown.MarkdownMemory;
pub const NoneMemory = none.NoneMemory;
pub const InMemoryLruMemory = memory_lru.InMemoryLruMemory;
pub const LucidMemory = lucid.LucidMemory;
pub const RedisMemory = redis.RedisMemory;
pub const ClickHouseMemory = clickhouse.ClickHouseMemory;
pub const LanceDbMemory = lancedb.LanceDbMemory;
pub const ApiMemory = api.ApiMemory;
pub const ResponseCache = cache.ResponseCache;
pub const Chunk = chunker.Chunk;
pub const chunkMarkdown = chunker.chunkMarkdown;
pub const EmbeddingProvider = embeddings.EmbeddingProvider;
pub const NoopEmbedding = embeddings.NoopEmbedding;
pub const cosineSimilarity = vector.cosineSimilarity;
pub const ScoredResult = vector.ScoredResult;
pub const hybridMerge = vector.hybridMerge;
pub const HygieneReport = hygiene.HygieneReport;
pub const exportSnapshot = snapshot.exportSnapshot;
pub const hydrateFromSnapshot = snapshot.hydrateFromSnapshot;
pub const shouldHydrate = snapshot.shouldHydrate;
pub const BackendDescriptor = registry.BackendDescriptor;
pub const BackendConfig = registry.BackendConfig;
pub const BackendInstance = registry.BackendInstance;
pub const BackendCapabilities = registry.BackendCapabilities;
pub const findBackend = registry.findBackend;
pub const RetrievalCandidate = retrieval.RetrievalCandidate;
pub const RetrievalSourceAdapter = retrieval.RetrievalSourceAdapter;
pub const PrimaryAdapter = retrieval.PrimaryAdapter;
pub const RetrievalEngine = retrieval.RetrievalEngine;
pub const QmdAdapter = retrieval_qmd.QmdAdapter;
pub const rrfMerge = rrf.rrfMerge;
pub const applyTemporalDecay = temporal_decay.applyTemporalDecay;
pub const VectorStore = vector_store.VectorStore;
pub const VectorResult = vector_store.VectorResult;
pub const HealthStatus = vector_store.HealthStatus;
pub const SqliteSharedVectorStore = vector_store.SqliteSharedVectorStore;
pub const SqliteSidecarVectorStore = vector_store.SqliteSidecarVectorStore;
pub const QdrantVectorStore = store_qdrant.QdrantVectorStore;
pub const freeVectorResults = vector_store.freeVectorResults;
pub const VectorOutbox = outbox.VectorOutbox;
pub const CircuitBreaker = circuit_breaker.CircuitBreaker;
pub const RolloutMode = rollout.RolloutMode;
pub const RolloutPolicy = rollout.RolloutPolicy;
pub const RolloutDecision = rollout.RolloutDecision;
pub const SqliteSourceEntry = migrate.SqliteSourceEntry;
pub const readBrainDb = migrate.readBrainDb;
pub const freeSqliteEntries = migrate.freeSqliteEntries;
pub const DiagnosticReport = diagnostics.DiagnosticReport;
pub const CacheStats = diagnostics.CacheStats;
pub const diagnoseRuntime = diagnostics.diagnose;
pub const formatDiagnosticReport = diagnostics.formatReport;

// Extended retrieval stages
pub const expandQuery = query_expansion.expandQuery;
pub const ExpandedQuery = query_expansion.ExpandedQuery;
pub const analyzeQuery = adaptive.analyzeQuery;
pub const AdaptiveConfig = adaptive.AdaptiveConfig;
pub const QueryAnalysis = adaptive.QueryAnalysis;
pub const RetrievalStrategy = adaptive.RetrievalStrategy;
pub const buildRerankPrompt = llm_reranker.buildRerankPrompt;
pub const parseRerankResponse = llm_reranker.parseRerankResponse;
pub const LlmRerankerConfig = llm_reranker.LlmRerankerConfig;

// Lifecycle: summarizer
pub const SummarizerConfig = summarizer.SummarizerConfig;
pub const SummaryResult = summarizer.SummaryResult;
pub const shouldSummarize = summarizer.shouldSummarize;
pub const buildSummarizationPrompt = summarizer.buildSummarizationPrompt;
pub const parseSummaryResponse = summarizer.parseSummaryResponse;

// Lifecycle: semantic cache
pub const SemanticCache = semantic_cache.SemanticCache;

// ── Session message types ─────────────────────────────────────────

pub const RUNTIME_COMMAND_ROLE = "__runtime_command__";

pub fn isRuntimeCommandRole(role: []const u8) bool

pub const MessageEntry = struct {

pub fn freeMessages(allocator: std.mem.Allocator, messages: []MessageEntry) void

/// Session summary for listing sessions.
pub const SessionInfo = struct {

pub fn freeSessionInfos(allocator: std.mem.Allocator, infos: []SessionInfo) void

/// Message with timestamp for detailed history.
pub const DetailedMessageEntry = struct {

pub fn freeDetailedMessages(allocator: std.mem.Allocator, entries: []DetailedMessageEntry) void

// ── SessionStore vtable interface ─────────────────────────────────

pub const SessionStore = struct {

// ── Memory categories ──────────────────────────────────────────────


    pub fn toString(self: MemoryCategory) []const u8

    pub fn fromString(s: []const u8) MemoryCategory

    pub fn eql(a: MemoryCategory, b: MemoryCategory) bool

// ── Memory entry ───────────────────────────────────────────────────

pub const MemoryEntry = struct {
    /// Free all allocated strings owned by this entry.

pub fn freeEntries(allocator: std.mem.Allocator, entries: []MemoryEntry) void

pub const PromptBootstrapKeyPrefix = "__bootstrap.prompt.";

pub const PromptBootstrapDoc = struct {


pub fn promptBootstrapMemoryKey(filename: []const u8) ?[]const u8

/// markdown and hybrid backends keep bootstrap identity in workspace files;
/// all other backends use backend-native key/value entries.
pub fn usesWorkspaceBootstrapFiles(memory_backend: ?[]const u8) bool

pub fn isInternalMemoryKey(key: []const u8) bool

pub fn extractMarkdownMemoryKey(content: []const u8) ?[]const u8

pub fn isInternalMemoryEntryKeyOrContent(key: []const u8, content: []const u8) bool

fn trimCandidatesToLimit(allocator: std.mem.Allocator, candidates: []RetrievalCandidate, limit: usize) ![]RetrievalCandidate

// ── Memory vtable interface ────────────────────────────────────────

pub const Memory = struct {

// ── MemoryRuntime — bundled memory + session store + capabilities ──

/// Resolved configuration snapshot — captures what was actually resolved during init.
/// Stored in MemoryRuntime for diagnostics, `/doctor`, and runtime inspection.
pub const ResolvedConfig = struct {

pub const MemoryRuntime = struct {
    // Internal: owned resources for cleanup
    // P5: rollout policy
    // Lifecycle: summarizer config
    // Lifecycle: semantic cache (optional, extends response cache with cosine similarity)
    // P3: vector plane components (all optional)
    /// High-level search: uses rollout policy to decide keyword-only vs hybrid.

const HygienePreserveSyncCtx = struct {

    // Durable mode: enqueue and return.

    const provider = embed_provider orelse return;
    const vs = vector_store_inst orelse return;





    const ctx: *HygienePreserveSyncCtx = @ptrCast(@alignCast(ctx_ptr));

/// Create a MemoryRuntime from a MemoryConfig and workspace directory.
/// Goes through the registry to find the backend, resolve paths, and
/// create the instance. Returns null on any error (unknown backend,
/// path resolution failure, backend init failure).
        const enabled_backends = registry.formatEnabledBackends(allocator) catch null;

            const engine_token = registry.engineTokenForBackend(config.backend) orelse config.backend;

    const pg_cfg: ?config_types.MemoryPostgresConfig = if (std.mem.eql(u8, config.backend, "postgres")) config.postgres else null;
    const redis_cfg: ?config_types.MemoryRedisConfig = if (std.mem.eql(u8, config.backend, "redis")) config.redis else null;
    const api_cfg: ?config_types.MemoryApiConfig = if (std.mem.eql(u8, config.backend, "api")) config.api else null;
    const clickhouse_cfg: ?config_types.MemoryClickHouseConfig = if (std.mem.eql(u8, config.backend, "clickhouse")) config.clickhouse else null;

            const db_path = if (cfg.db_path) |p| std.mem.span(p) else "(unknown path)";

    // ── Lifecycle: snapshot hydrate (before hygiene) ──

    // ── Lifecycle: response cache ──
    var resp_cache: ?*cache.ResponseCache = null;
    var cache_db_path: ?[*:0]const u8 = null;
        const cp_slice = std.fs.path.joinZ(allocator, &.{

    // ── Retrieval engine ──
    var engine: ?*retrieval.RetrievalEngine = null;
        const eng = allocator.create(retrieval.RetrievalEngine) catch break :build_engine;

        // Add primary adapter unless QMD-only mode is explicitly requested.
        const include_primary = !config.qmd.enabled or config.qmd.include_default_memory;

        // QMD adapter (optional — alloc failure just skips it, engine remains usable)

        // Configure extended pipeline stages (query expansion, adaptive, LLM reranker)


    // ── P3: Vector plane wiring ──
    var embed_provider: ?embeddings.EmbeddingProvider = null;
    var vs_iface: ?vector_store.VectorStore = null;
    var cb_inst: ?*circuit_breaker.CircuitBreaker = null;
    var outbox_inst: ?*outbox.VectorOutbox = null;
    var sidecar_db_path: ?[*:0]const u8 = null;
    var resolved_vector_mode: []const u8 = "none";
    var resolved_vector_sync_mode: []const u8 = "best_effort";
        const primary_api_key = provider_api_key.resolveApiKey(allocator, config.search.provider, null) catch null;

        // 1. Create EmbeddingProvider (with optional fallback via ProviderRouter)


        // Wrap primary + fallback in a ProviderRouter when fallback is configured
            const fallback_api_key = provider_api_key.resolveApiKey(allocator, config.search.fallback_provider, null) catch null;


        // 2. Resolve vector store mode based on config.search.store.kind
        //    "auto"           → sqlite_shared if primary is sqlite-based, else sqlite_sidecar
        //    "qdrant"         → QdrantVectorStore via REST API
        //    "pgvector"       → PgvectorVectorStore via libpq (requires enable_postgres)
        //    "sqlite_shared"  → explicit sqlite shared (requires sqlite-based primary)
        //    "sqlite_sidecar" → explicit sqlite sidecar (separate vectors.db)
        //    "sqlite_ann"     → sqlite shared + ANN prefilter (experimental)
        var db_handle_for_outbox: ?*c.sqlite3 = null;
        const store_kind = config.search.store.kind;

            // Qdrant via REST API
            // pgvector via PostgreSQL
            // auto / sqlite_shared / sqlite_sidecar
                    const vs = allocator.create(vector_store.SqliteAnnVectorStore) catch break :vec_plane;
                const use_shared = std.mem.eql(u8, store_kind, "auto") or std.mem.eql(u8, store_kind, "sqlite_shared");
                        // sqlite_shared: reuse existing sqlite db handle
                        const vs = allocator.create(vector_store.SqliteSharedVectorStore) catch break :vec_plane;
                    // else: auto fallthrough to sidecar below

                // sqlite_sidecar: explicit or auto fallback for non-sqlite backends
                        const configured = config.search.store.sidecar_path;
                    const sidecar_path: [*:0]const u8 = sidecar_path_slice.ptr;

        // 3. Create CircuitBreaker
        const cb = allocator.create(circuit_breaker.CircuitBreaker) catch break :vec_plane;

        // 4. Create VectorOutbox if not best_effort
                const ob = allocator.create(outbox.VectorOutbox) catch break :vec_plane;
                const outbox_retries = @max(config.search.sync.embed_max_retries, config.search.sync.vector_max_retries);

        // 5. Wire into retrieval engine

    // ── Lifecycle: hygiene ──
        const report = hygiene.runIfDue(allocator, hygiene_cfg, instance.memory, preserve_sync_hook);

        // Snapshot after hygiene if configured and hygiene did work

    // Enforce fallback_policy: if fail_fast and vector plane was expected but failed, abort.
        const durable_requested = !std.mem.eql(u8, config.search.sync.mode, "best_effort");
        const vector_plane_failed = vector_expected and vs_iface == null;
        const durable_outbox_unavailable = vector_expected and durable_requested and outbox_inst == null;
            // Clean up partially-created P3 resources
            // Clean up response cache

    // Free postgres_url after backend creation (backend dupes what it needs)

    // ── Lifecycle: semantic cache ──
    var sem_cache: ?*semantic_cache.SemanticCache = null;
    var sem_cache_db_path: ?[*:0]const u8 = null;
        const sc_path = std.fs.path.joinZ(allocator, &.{

    // ── Lifecycle: summarizer config ──

    // ── Startup diagnostic ──
    const source_count: usize = if (engine) |eng| eng.sources.items.len else 0;
    const vector_mode: []const u8 = if (vs_iface == null) "none" else resolved_vector_mode;
    const cache_enabled = resp_cache != null;

    const embed_name: []const u8 = if (embed_provider) |ep_| ep_.getName() else "none";


// ── Helpers ────────────────────────────────────────────────────────

const c = sqlite.c;

/// Extract the raw sqlite3* handle from a Memory vtable, if the backend is sqlite-based.
fn extractSqliteDb(mem: Memory) ?*c.sqlite3

// ── Tests ──────────────────────────────────────────────────────────


test "MemoryCategory toString roundtrip" {
    const core: MemoryCategory = .core;

    const daily: MemoryCategory = .daily;

    const conversation: MemoryCategory = .conversation;

    const custom: MemoryCategory = .{

test "MemoryCategory fromString" {
    const core = MemoryCategory.fromString("core");

    const daily = MemoryCategory.fromString("daily");

    const conversation = MemoryCategory.fromString("conversation");

    const custom = MemoryCategory.fromString("project");

test "MemoryCategory equality" {
    const core: MemoryCategory = .core;
    const c1: MemoryCategory = .{

test "MemoryCategory custom toString" {
    const cat: MemoryCategory = .{

test "MemoryCategory fromString custom" {
    const cat = MemoryCategory.fromString("unknown_category");

test "MemoryCategory eql different tags" {
    const core: MemoryCategory = .core;
    const daily: MemoryCategory = .daily;
    const conv: MemoryCategory = .conversation;

test "Memory convenience store accepts session_id" {
    var backend = none.NoneMemory.init();
    const m = backend.memory();

test "Memory convenience recall accepts session_id" {
    var backend = none.NoneMemory.init();
    const m = backend.memory();
    const results = try m.recall(std.testing.allocator, "query", 5, null);

    const results2 = try m.recall(std.testing.allocator, "query", 5, "session-abc");

test "Memory convenience list accepts session_id" {
    var backend = none.NoneMemory.init();
    const m = backend.memory();
    const results = try m.list(std.testing.allocator, null, null);

    const results2 = try m.list(std.testing.allocator, .core, "session-abc");

test "SessionStore delegates through vtable" {
    const TestSessionStore = struct {

    var mock = TestSessionStore{

test "freeMessages frees all entries" {
    const allocator = std.testing.allocator;
    var messages = try allocator.alloc(MessageEntry, 2);
    // No leak = pass (allocator is testing allocator with leak detection)

fn requireBackendEnabledForTests(name: []const u8) !void

const TestTmpDir = @TypeOf(std.testing.tmpDir(.{