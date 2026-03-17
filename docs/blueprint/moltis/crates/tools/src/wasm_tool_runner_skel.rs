#[cfg(feature = "wasm")]
use std::{
    collections::HashMap,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

#[cfg(feature = "wasm")]
use {
    anyhow::{Context, Result, bail},
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    serde_json::Value,
};

#[cfg(feature = "wasm")]
use crate::{
    wasm_component::{HttpHostImpl, HttpToolResult, PureToolResult, http_tool, pure_tool},
    wasm_engine::{WasmComponentEngine, hash_component_bytes},
    wasm_limits::WasmResourceLimiter,
};

// ---------------------------------------------------------------------------
// Unified store state
// ---------------------------------------------------------------------------

#[cfg(feature = "wasm")]
struct WasmStoreState {
    ...
}

#[cfg(feature = "wasm")]
impl WasmStoreState {
    fn new(memory_limit_bytes: usize, http_host: Option<HttpHostImpl>) -> Self {
}

#[cfg(feature = "wasm")]
impl wasmtime_wasi::WasiView for WasmStoreState {
    fn ctx(&mut self) -> wasmtime_wasi::WasiCtxView<'_> {
}

// ---------------------------------------------------------------------------
// Epoch ticker (unchanged)
// ---------------------------------------------------------------------------

#[cfg(feature = "wasm")]
struct EpochTicker {
    ...
}

#[cfg(feature = "wasm")]
impl EpochTicker {
    fn start(engine: wasmtime::Engine, timeout: Duration, interval_ms: u64) -> Self {
}

#[cfg(feature = "wasm")]
impl Drop for EpochTicker {
    fn drop(&mut self) {
}

// ---------------------------------------------------------------------------
// Unified WasmToolRunner
// ---------------------------------------------------------------------------

/// Host adapter that executes a WASM component as an `AgentTool`.
///
/// When `http_host` is `None` the component is instantiated as a `pure-tool`;
/// when `Some` it is instantiated as an `http-tool` with host-side HTTP.
#[cfg(feature = "wasm")]
pub struct WasmToolRunner {
    ...
}

#[cfg(feature = "wasm")]
struct CachedResult {
    ...
}

#[cfg(feature = "wasm")]
pub struct CachingWasmToolRunner {
    ...
}

#[cfg(feature = "wasm")]
impl WasmToolRunner {
    /// Create a pure-tool runner (no HTTP capability).
    pub fn new(
        engine: Arc<WasmComponentEngine>,
        wasm_bytes: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
    ) -> Result<Self> {

    /// Create an HTTP-capable tool runner.
    pub fn new_http(
        engine: Arc<WasmComponentEngine>,
        wasm_bytes: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
        http_host: HttpHostImpl,
    ) -> Result<Self> {
    ...
}

    /// Create a pure-tool runner from pre-compiled `.cwasm` bytes (AOT, no Cranelift at runtime).
    ///
    /// # Safety
    /// `precompiled` must originate from `Engine::precompile_component` with the same config.
    #[allow(unsafe_code)]
    pub unsafe fn new_precompiled(
        engine: Arc<WasmComponentEngine>,
        precompiled: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
    ) -> Result<Self> {
    ...
}

    /// Create an HTTP-capable tool runner from pre-compiled `.cwasm` bytes (AOT).
    ///
    /// # Safety
    /// `precompiled` must originate from `Engine::precompile_component` with the same config.
    #[allow(unsafe_code)]
    pub unsafe fn new_http_precompiled(
        engine: Arc<WasmComponentEngine>,
        precompiled: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
        http_host: HttpHostImpl,
    ) -> Result<Self> {
    ...
}

    fn new_inner(
        engine: Arc<WasmComponentEngine>,
        wasm_bytes: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
        http_host: Option<HttpHostImpl>,
    ) -> Result<Self> {
    ...
}

    /// Inner constructor for pre-compiled (AOT) components.
    ///
    /// # Safety
    /// `precompiled` must originate from `Engine::precompile_component` with the same config.
    #[allow(unsafe_code)]
    unsafe fn new_inner_precompiled(
        engine: Arc<WasmComponentEngine>,
        precompiled: &[u8],
        fuel_limit: u64,
        memory_limit_bytes: usize,
        timeout: Duration,
        epoch_interval_ms: u64,
        http_host: Option<HttpHostImpl>,
    ) -> Result<Self> {
    ...
}

    #[must_use]
    pub fn component_hash(&self) -> [u8; 32] {
    ...
}

    fn load_metadata(
        engine: &WasmComponentEngine,
        component: &wasmtime::component::Component,
        memory_limit_bytes: usize,
        http_host: Option<&HttpHostImpl>,
    ) -> Result<WasmToolMetadata> {
    ...
}

    fn execute_blocking(&self, params: Value) -> Result<Value> {
    ...
}

    fn clone_for_blocking(&self) -> Self {
    ...
}
}

#[cfg(feature = "wasm")]
#[async_trait]
impl AgentTool for WasmToolRunner {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> Result<Value> {
    ...
}
}

// ---------------------------------------------------------------------------
// CachingWasmToolRunner
// ---------------------------------------------------------------------------

#[cfg(feature = "wasm")]
impl CachingWasmToolRunner {
    pub fn new(inner: Arc<dyn AgentTool>, component_hash: [u8; 32], cache_ttl: Duration) -> Self {

    #[must_use]
    pub fn component_hash(&self) -> [u8; 32] {
    ...
}

    fn cache_get(&self, key: &str) -> Option<Value> {
    ...
}

    fn cache_set(&self, key: String, value: Value) {
    ...
}
}

#[cfg(feature = "wasm")]
#[async_trait]
impl AgentTool for CachingWasmToolRunner {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> Result<Value> {
    ...
}
}

// ---------------------------------------------------------------------------
// Registration helper — called from server.rs
// ---------------------------------------------------------------------------

/// Register all embedded WASM tools into `registry`.
///
/// Individual tool failures are logged but do not abort the entire registration.
#[cfg(feature = "wasm")]
pub fn register_wasm_tools(
    registry: &mut moltis_agents::tool_registry::ToolRegistry,
    wasm_limits: &crate::wasm_limits::WasmToolLimits,
    epoch_interval_ms: u64,
    fetch_timeout_secs: u64,
    fetch_cache_ttl_minutes: u64,
    search_timeout_secs: u64,
    search_cache_ttl_minutes: u64,
    search_api_key: Option<&str>,
) -> Result<()> {
    ...
}

// ---------------------------------------------------------------------------
// Internals: instance dispatch, store/linker helpers, result marshaling
// ---------------------------------------------------------------------------

#[cfg(feature = "wasm")]
struct WasmToolMetadata {
    ...
}

#[cfg(feature = "wasm")]
const METADATA_FUEL_BUDGET: u64 = 50_000_000;
#[cfg(feature = "wasm")]
const METADATA_EPOCH_DEADLINE_TICKS: u64 = 1_000_000;
#[cfg(feature = "wasm")]
const MAX_CACHE_ENTRIES_BEFORE_EVICTION: usize = 200;

/// Dispatches between pure-tool and http-tool component instances.
#[cfg(feature = "wasm")]
enum WasmToolInstance {
    ...
}

#[cfg(feature = "wasm")]
impl WasmToolInstance {
    fn instantiate(
        engine: &WasmComponentEngine,
        store: &mut wasmtime::Store<WasmStoreState>,
        component: &wasmtime::component::Component,
        label: &str,
    ) -> Result<Self> {

    fn call_name(&self, store: &mut wasmtime::Store<WasmStoreState>) -> Result<String> {
    ...
}

    fn call_description(&self, store: &mut wasmtime::Store<WasmStoreState>) -> Result<String> {
    ...
}

    fn call_parameters_schema(
        &self,
        store: &mut wasmtime::Store<WasmStoreState>,
    ) -> Result<String> {
    ...
}

    fn call_execute(
        &self,
        store: &mut wasmtime::Store<WasmStoreState>,
        params_json: &str,
    ) -> Result<ToolResult> {
    ...
}
}

/// Unified result type for both pure-tool and http-tool components.
#[cfg(feature = "wasm")]
enum ToolResult {
    ...
}

#[cfg(feature = "wasm")]
impl ToolResult {
    fn from_pure(result: PureToolResult) -> Self {

    fn from_http(result: HttpToolResult) -> Self {
    ...
}
}

/// Marshal a `PureToolValue` into `serde_json::Value`.
#[cfg(feature = "wasm")]
fn marshal_pure_value(value: crate::wasm_component::PureToolValue) -> Value {
    ...
}

/// Marshal an `HttpToolValue` into `serde_json::Value`.
#[cfg(feature = "wasm")]
fn marshal_http_value(value: crate::wasm_component::HttpToolValue) -> Value {
    ...
}

#[cfg(feature = "wasm")]
fn decode_tool_result(tool_name: &str, result: ToolResult) -> Result<Value> {
    ...
}

#[cfg(feature = "wasm")]
fn new_store(
    engine: &wasmtime::Engine,
    memory_limit_bytes: usize,
    http_host: Option<HttpHostImpl>,
) -> wasmtime::Store<WasmStoreState> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(all(test, feature = "wasm"))]
mod tests {

    fn maybe_calc_runner(fuel_limit: u64) -> Option<WasmToolRunner> {
    ...
}

    #[test]
    fn decode_result_maps_ok_value() {
    ...
}

    #[test]
    fn decode_result_maps_err_variant() {
    ...
}

    #[tokio::test]
    async fn calc_wasm_matches_native_for_expressions() {
    ...
}

    #[tokio::test]
    async fn calc_wasm_low_fuel_fails() {
    ...
}

    struct EchoTool {
    ...
}

    #[async_trait::async_trait]
    impl AgentTool for EchoTool {
        fn name(&self) -> &str {

        fn description(&self) -> &str {
    ...
}

        fn parameters_schema(&self) -> serde_json::Value {
    ...
}

        async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
    }

    #[tokio::test]
    async fn caching_runner_returns_cached_value() {
    ...
}

    // --- marshal_http_value tests ---

    #[test]
    fn marshal_http_value_text() {
    ...
}

    #[test]
    fn marshal_http_value_number() {
    ...
}

    #[test]
    fn marshal_http_value_integer() {
    ...
}

    #[test]
    fn marshal_http_value_boolean() {
    ...
}

    #[test]
    fn marshal_http_value_json() {
    ...
}

    #[test]
    fn marshal_http_value_nan_becomes_null() {
    ...
}

    #[test]
    fn marshal_http_value_invalid_json_becomes_string() {
    ...
}

    // --- marshal_pure_value edge-case tests ---

    #[test]
    fn marshal_pure_value_nan_becomes_null() {
    ...
}

    #[test]
    fn marshal_pure_value_invalid_json_becomes_string() {
    ...
}