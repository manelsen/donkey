//! C ABI bridge for embedding Moltis Rust functionality into native Swift apps.

use std::{
    collections::HashMap,
    ffi::{CStr, CString, c_char, c_void},
    net::SocketAddr,
    panic::{AssertUnwindSafe, catch_unwind},
    sync::{Arc, LazyLock, Mutex, OnceLock, RwLock},
};

use {
    moltis_agents::model::{
        ChatMessage as AgentChatMessage, LlmProvider, StreamEvent, Usage, UserContent,
    },
    moltis_config::validate::Severity,
    moltis_provider_setup::{
        KeyStore, config_with_saved_keys, detect_auto_provider_sources_with_overrides,
        known_providers,
    },
    moltis_providers::ProviderRegistry,
    moltis_sessions::{
        message::PersistedMessage,
        metadata::{SessionEntry, SqliteSessionMetadata},
        session_events::{SessionEvent, SessionEventBus},
        store::SessionStore,
    },
    moltis_tools::image_cache::ImageBuilder,
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
    tokio_stream::StreamExt,
};

// ── Global bridge state ────────────────────────────────────────────────────

struct BridgeState {
    ...
}

impl BridgeState {
    fn new() -> Self {
        #[cfg(test)]
}

#[cfg(test)]
fn init_swift_bridge_test_dirs() {
    ...
}

fn build_registry() -> ProviderRegistry {
    ...
}

static BRIDGE: LazyLock<BridgeState> = LazyLock::new(BridgeState::new);

// ── HTTP Server ──────────────────────────────────────────────────────────

/// Handle to a running httpd server, used to shut it down.
struct HttpdHandle {
    ...
}

/// Global server handle — `None` when stopped, `Some` when running.
static HTTPD: Mutex<Option<HttpdHandle>> = Mutex::new(None);

#[derive(Debug, Deserialize)]
struct StartHttpdRequest {
    ...
}

fn default_httpd_host() -> String {
    ...
}

fn default_httpd_port() -> u16 {
    ...
}

#[derive(Debug, Serialize)]
struct HttpdStatusResponse {
    ...
}

// ── Log callback for Swift ───────────────────────────────────────────────

/// Callback type for forwarding log events to Swift. Rust owns the
/// `log_json` pointer — the callback must copy the data before returning.
#[allow(unsafe_code)]
type LogCallback = unsafe extern "C" fn(log_json: *const c_char);

static LOG_CALLBACK: OnceLock<LogCallback> = OnceLock::new();

/// JSON-serializable log event sent to Swift.
#[derive(Debug, Serialize)]
struct BridgeLogEvent<'a> {
    ...
}

fn emit_log(level: &str, target: &str, message: &str) {
    ...
}

#[allow(unsafe_code)]
fn emit_log_with_fields(
    level: &str,
    target: &str,
    message: &str,
    fields: Option<&HashMap<&str, String>>,
) {
    ...
}

// ── Session event callback for Swift ─────────────────────────────────────

/// Callback type for forwarding session events to Swift.
/// Rust owns the `event_json` pointer — the callback must copy the data
/// before returning.
#[allow(unsafe_code)]
type SessionEventCallback = unsafe extern "C" fn(event_json: *const c_char);

static SESSION_EVENT_CALLBACK: OnceLock<SessionEventCallback> = OnceLock::new();

/// JSON payload sent to Swift for each session event.
#[derive(Debug, Serialize)]
struct BridgeSessionEvent {
    ...
}

#[allow(unsafe_code)]
fn emit_session_event(event: &SessionEvent) {
    ...
}

// ── Network audit callback for Swift ─────────────────────────────────────

/// Callback type for forwarding network audit events to Swift.
/// Rust owns the `event_json` pointer — the callback must copy the data
/// before returning.
#[allow(unsafe_code)]
type NetworkAuditCallback = unsafe extern "C" fn(event_json: *const c_char);

static NETWORK_AUDIT_CALLBACK: OnceLock<NetworkAuditCallback> = OnceLock::new();

/// JSON-serializable network audit event sent to Swift.
#[derive(Debug, Serialize)]
struct BridgeNetworkAuditEvent {
    ...
}

#[allow(unsafe_code)]
fn emit_network_audit(entry: &moltis_network_filter::NetworkAuditEntry) {
    ...
}

// ── Request / Response types ───────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ChatRequest {
    ...
}

#[derive(Debug, Serialize)]
struct ChatResponse {
    ...
}

#[derive(Debug, Serialize)]
struct ValidationSummary {
    ...
}

#[derive(Debug, Serialize)]
struct VersionResponse {
    ...
}

// ── Session types ──────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct SwitchSessionRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct CreateSessionRequest {
    ...
}

/// Compact session entry for the Swift side.
#[derive(Debug, Serialize)]
struct BridgeSessionEntry {
    ...
}

impl From<&SessionEntry> for BridgeSessionEntry {
    fn from(e: &SessionEntry) -> Self {
}

/// Session history: entry + messages.
#[derive(Debug, Serialize)]
struct BridgeSessionHistory {
    ...
}

/// Chat request with session key.
#[derive(Debug, Deserialize)]
struct SessionChatRequest {
    ...
}

#[derive(Debug, Serialize)]
struct ErrorEnvelope<'a> {
    ...
}

#[derive(Debug, Serialize)]
struct ErrorPayload<'a> {
    ...
}

// ── Bridge serde types for provider data ───────────────────────────────────

#[derive(Debug, Serialize)]
struct BridgeKnownProvider {
    ...
}

#[derive(Debug, Serialize)]
struct BridgeDetectedSource {
    ...
}

#[derive(Debug, Serialize)]
struct BridgeModelInfo {
    ...
}

#[derive(Deserialize)]
struct SaveProviderRequest {
    ...
}

impl std::fmt::Debug for SaveProviderRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

#[derive(Debug, Serialize)]
struct OkResponse {
    ...
}

// ── Config / Identity / Soul request/response types ─────────────────────

#[derive(Debug, Serialize)]
struct GetConfigResponse {
    ...
}

#[derive(Debug, Serialize)]
struct GetSoulResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SaveSoulRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct SaveIdentityRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct SaveUserProfileRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct SetEnvVarRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct DeleteEnvVarRequest {
    ...
}

#[derive(Debug, Serialize)]
struct ListEnvVarsResponse {
    ...
}

#[derive(Debug, Serialize)]
struct MemoryStatusResponse {
    ...
}

#[derive(Debug, Serialize)]
struct MemoryConfigResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct MemoryConfigUpdateRequest {
    ...
}

#[derive(Debug, Serialize)]
struct MemoryQmdStatusResponse {
    ...
}

#[derive(Debug, Serialize)]
struct AuthStatusResponse {
    ...
}

#[derive(Deserialize)]
struct AuthPasswordChangeRequest {
    ...
}

impl std::fmt::Debug for AuthPasswordChangeRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

#[derive(Debug, Serialize)]
struct AuthPasswordChangeResponse {
    ...
}

#[derive(Debug, Serialize)]
struct AuthPasskeysResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct AuthPasskeyIdRequest {
    ...
}

#[derive(Debug, Deserialize)]
struct AuthPasskeyRenameRequest {
    ...
}

const IMAGE_CACHE_DELETE_FAILED: &str = "IMAGE_CACHE_DELETE_FAILED";
const IMAGE_CACHE_PRUNE_FAILED: &str = "IMAGE_CACHE_PRUNE_FAILED";
const SANDBOX_CHECK_PACKAGES_FAILED: &str = "SANDBOX_CHECK_PACKAGES_FAILED";
const SANDBOX_BACKEND_UNAVAILABLE: &str = "SANDBOX_BACKEND_UNAVAILABLE";
const SANDBOX_IMAGE_NAME_REQUIRED: &str = "SANDBOX_IMAGE_NAME_REQUIRED";
const SANDBOX_IMAGE_PACKAGES_REQUIRED: &str = "SANDBOX_IMAGE_PACKAGES_REQUIRED";
const SANDBOX_IMAGE_NAME_INVALID: &str = "SANDBOX_IMAGE_NAME_INVALID";
const SANDBOX_TMP_DIR_CREATE_FAILED: &str = "SANDBOX_TMP_DIR_CREATE_FAILED";
const SANDBOX_DOCKERFILE_WRITE_FAILED: &str = "SANDBOX_DOCKERFILE_WRITE_FAILED";
const SANDBOX_IMAGE_BUILD_FAILED: &str = "SANDBOX_IMAGE_BUILD_FAILED";
const SANDBOX_CONTAINERS_LIST_FAILED: &str = "SANDBOX_CONTAINERS_LIST_FAILED";
const SANDBOX_CONTAINER_PREFIX_MISMATCH: &str = "SANDBOX_CONTAINER_PREFIX_MISMATCH";
const SANDBOX_CONTAINER_STOP_FAILED: &str = "SANDBOX_CONTAINER_STOP_FAILED";
const SANDBOX_CONTAINER_REMOVE_FAILED: &str = "SANDBOX_CONTAINER_REMOVE_FAILED";
const SANDBOX_CONTAINERS_CLEAN_FAILED: &str = "SANDBOX_CONTAINERS_CLEAN_FAILED";
const SANDBOX_DISK_USAGE_FAILED: &str = "SANDBOX_DISK_USAGE_FAILED";
const SANDBOX_DAEMON_RESTART_FAILED: &str = "SANDBOX_DAEMON_RESTART_FAILED";
const SANDBOX_SHARED_HOME_SAVE_FAILED: &str = "SANDBOX_SHARED_HOME_SAVE_FAILED";
const SANDBOX_PACKAGE_NAME_INVALID: &str = "SANDBOX_PACKAGE_NAME_INVALID";
const SANDBOX_BASE_IMAGE_INVALID: &str = "SANDBOX_BASE_IMAGE_INVALID";

/// Validates a package name to prevent shell injection.
/// Allows alphanumeric, hyphen, dot, plus, colon (covers dpkg naming conventions).
fn is_valid_package_name(name: &str) -> bool {
    ...
}

/// Validates a container/base image reference (e.g. "ubuntu:25.10", "docker.io/library/ubuntu").
/// Allows alphanumeric, hyphen, dot, colon, slash, underscore.
fn is_valid_image_ref(name: &str) -> bool {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxStatusResponse {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxImageEntry {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxImagesResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxDeleteImageRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxPruneImagesResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxCheckPackagesRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxCheckPackagesResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxBuildImageRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxBuildImageResponse {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxDefaultImageResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxSetDefaultImageRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxSharedHomeConfigResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxSharedHomeUpdateRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxSharedHomeSaveResponse {
    ...
}

#[derive(Debug, Deserialize)]
struct SandboxContainerNameRequest {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxContainersResponse {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxCleanContainersResponse {
    ...
}

#[derive(Debug, Serialize)]
struct SandboxDiskUsageResponse {
    ...
}

// ── Encoding helpers ───────────────────────────────────────────────────────

fn encode_json<T: Serialize>(value: &T) -> String {
    match serde_json::to_string(value) {
        Ok(json) => json,
        Err(_) => {
            "{\"error\":{\"code\":\"serialization_error\",\"message\":\"failed to serialize response\"}}"
                .to_owned()
        }
    }
}

fn encode_error(code: &str, message: &str) -> String {
    ...
}

fn into_c_ptr(payload: String) -> *mut c_char {
    ...
}

fn with_ffi_boundary<F>(work: F) -> *mut c_char
where
    F: FnOnce() -> String,
{
    match catch_unwind(AssertUnwindSafe(work)) {
        Ok(payload) => into_c_ptr(payload),
        Err(_) => into_c_ptr(encode_error(
            "panic",
            "unexpected panic occurred in Rust FFI boundary",
        )),
    }
}

/// Parses a C string JSON pointer into a typed request, recording errors
/// against `function` for metrics. Returns `Err(encoded_error_json)` on
/// failure so callers can early-return from `with_ffi_boundary`.
fn parse_ffi_request<T: serde::de::DeserializeOwned>(
    function: &'static str,
    ptr: *const c_char,
) -> Result<T, String> {
    let raw = read_c_string(ptr).map_err(|message| {
        record_error(function, "null_pointer_or_invalid_utf8");
        encode_error("null_pointer_or_invalid_utf8", &message)
    })?;
    serde_json::from_str::<T>(&raw).map_err(|error| {
        record_error(function, "invalid_json");
        encode_error("invalid_json", &error.to_string())
    })
}

#[allow(unsafe_code)]
fn read_c_string(ptr: *const c_char) -> Result<String, String> {
    ...
}

fn format_bytes(bytes: u64) -> String {
    ...
}

fn build_validation_summary(config_toml: Option<&str>) -> Option<ValidationSummary> {
    ...
}

fn config_dir_string() -> String {
    ...
}

fn data_dir_string() -> String {
    ...
}

fn vault_status_string() -> String {
    ...
}

fn sandbox_effective_default_image(config: &moltis_config::MoltisConfig) -> String {
    ...
}

fn sandbox_backend_name(config: &moltis_config::MoltisConfig) -> String {
    ...
}

fn sandbox_status_from_config(config: &moltis_config::MoltisConfig) -> SandboxStatusResponse {
    ...
}

fn sandbox_container_prefix(config: &moltis_config::MoltisConfig) -> String {
    ...
}

fn sandbox_shared_home_config_from_config(
    config: &moltis_config::MoltisConfig,
) -> SandboxSharedHomeConfigResponse {
    ...
}

// ── Chat with real LLM ────────────────────────────────────────────────────

fn resolve_provider(request: &ChatRequest) -> Option<std::sync::Arc<dyn LlmProvider>> {
    ...
}

fn resolve_provider_for_model(model: Option<&str>) -> Option<std::sync::Arc<dyn LlmProvider>> {
    ...
}

fn build_chat_response(request: ChatRequest) -> String {
    ...
}

// ── Streaming support ──────────────────────────────────────────────────────

/// Callback type for streaming events. Rust owns the `event_json` pointer —
/// the callback must copy the data before returning; Rust drops it afterwards.
#[allow(unsafe_code)]
type StreamCallback = unsafe extern "C" fn(event_json: *const c_char, user_data: *mut c_void);

/// JSON-serializable event sent to Swift via the callback.
#[derive(Debug, Serialize)]
#[serde(tag = "type")]
enum BridgeStreamEvent {
    ...
}

/// Bundle of callback + user_data that can cross the `tokio::spawn` boundary.
///
/// # Safety
///
/// The Swift side guarantees that `user_data` remains valid until a terminal
/// event (done/error) is received, and the callback function pointer is
/// stable for the lifetime of the stream. The callback dispatches to the
/// main thread so there is no concurrent access.
struct StreamCallbackCtx {
    ...
}

// SAFETY: See struct doc — Swift retains `StreamContext` via
// `Unmanaged.passRetained` and the callback itself is a plain function pointer.
#[allow(unsafe_code)]
unsafe impl Send for StreamCallbackCtx {}

#[allow(unsafe_code)]
impl StreamCallbackCtx {
    fn send(&self, event: &BridgeStreamEvent) {
    ...
}
}

/// Start a streaming LLM chat. Events are delivered via `callback`. The
/// function returns immediately; the stream runs on the bridge's tokio
/// runtime. The caller must keep `user_data` alive until a terminal event
/// (done or error) is delivered.
///
/// # Safety
///
/// * `request_json` must be a valid NUL-terminated C string.
/// * `callback` must be a valid function pointer that remains valid for the
///   lifetime of the stream.
/// * `user_data` must remain valid until the callback receives a terminal
///   event (done or error).
#[allow(unsafe_code)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn moltis_chat_stream(
    request_json: *const c_char,
    callback: StreamCallback,
    user_data: *mut c_void,
) {
    ...
}

// ── Metrics / tracing helpers ──────────────────────────────────────────────

#[cfg(feature = "metrics")]
fn record_call(function: &'static str) {
    ...
}

#[cfg(not(feature = "metrics"))]
fn record_call(_function: &'static str) {
    ...
}