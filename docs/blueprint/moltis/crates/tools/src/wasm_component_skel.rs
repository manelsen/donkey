#[cfg(feature = "wasm")]
use std::{
    collections::{HashMap, HashSet},
    io::Read,
    thread,
    time::Duration,
};

#[cfg(feature = "wasm")]
use anyhow::Context;

#[cfg(feature = "wasm")]
use crate::ssrf::ssrf_check_blocking;

#[cfg(feature = "wasm")]
pub mod pure_tool {
    wasmtime::component::bindgen!({
        path: "../../wit",
        world: "pure-tool",
    });
}

#[cfg(feature = "wasm")]
pub mod http_tool {
    wasmtime::component::bindgen!({
        path: "../../wit",
        world: "http-tool",
    });
}

#[cfg(feature = "wasm")]
pub type PureToolValue = pure_tool::moltis::tool::types::ToolValue;
#[cfg(feature = "wasm")]
pub type PureToolResult = pure_tool::moltis::tool::types::ToolResult;
#[cfg(feature = "wasm")]
pub type PureToolError = pure_tool::moltis::tool::types::ToolError;
#[cfg(feature = "wasm")]
pub type HttpRequest = http_tool::moltis::tool::outgoing_handler::HttpRequest;
#[cfg(feature = "wasm")]
pub type HttpResponse = http_tool::moltis::tool::outgoing_handler::HttpResponse;
#[cfg(feature = "wasm")]
pub type HttpError = http_tool::moltis::tool::outgoing_handler::HttpError;
#[cfg(feature = "wasm")]
pub type HttpToolValue = http_tool::moltis::tool::types::ToolValue;
#[cfg(feature = "wasm")]
pub type HttpToolResult = http_tool::moltis::tool::types::ToolResult;
#[cfg(feature = "wasm")]
pub type HttpToolError = http_tool::moltis::tool::types::ToolError;

/// Host-injected headers keyed by lowercase domain.
///
/// For each matching domain the host silently adds (or overrides) headers on
/// outgoing requests. This keeps secrets like API keys out of guest parameters.
#[cfg(feature = "wasm")]
pub type SecretHeaders = HashMap<String, Vec<(String, String)>>;

#[cfg(feature = "wasm")]
#[derive(Clone)]
pub struct HttpHostImpl {
    ...
}

#[cfg(feature = "wasm")]
impl HttpHostImpl {
    pub fn new(
        timeout: Duration,
        max_response_bytes: usize,
        ssrf_allowlist: Vec<ipnet::IpNet>,
        domain_allowlist: Option<Vec<String>>,
        secret_headers: SecretHeaders,
    ) -> anyhow::Result<Self> {
        fn build_blocking_client(timeout: Duration) -> anyhow::Result<reqwest::blocking::Client> {
    ...
}

        let max_response_bytes = u64::try_from(max_response_bytes)
            .context("max_response_bytes does not fit into u64")?;
        let domain_allowlist = domain_allowlist.map(|domains| {
            domains
                .into_iter()
                .map(|domain| domain.trim().to_ascii_lowercase())
                .filter(|domain| !domain.is_empty())
                .collect::<HashSet<_>>()
        });
        let client = if tokio::runtime::Handle::try_current().is_ok() {
            thread::Builder::new()
                .name("moltis-wasm-http-client-init".to_string())
                .spawn(move || build_blocking_client(timeout))
                .context("failed to spawn blocking HTTP client init thread")?
                .join()
                .map_err(|_| anyhow::anyhow!("blocking HTTP client init thread panicked"))??
        } else {
            build_blocking_client(timeout)?
        };
        Ok(Self {
            client,
            ssrf_allowlist,
            max_response_bytes,
            domain_allowlist,
            secret_headers,
        })
    }

    fn domain_allowed(&self, host: &str) -> bool {
    ...
}

    fn map_request_error(error: reqwest::Error) -> HttpError {
    ...
}

    fn map_io_error(error: std::io::Error) -> HttpError {
    ...
}

    fn resolve_max_response_bytes(&self, requested: Option<u64>) -> u64 {
    ...
}

    pub fn handle_request(&self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
    ...
}
}

#[cfg(feature = "wasm")]
impl http_tool::moltis::tool::outgoing_handler::Host for HttpHostImpl {
    fn handle(&mut self, request: HttpRequest) -> Result<HttpResponse, HttpError> {
}

#[cfg(feature = "wasm")]
pub fn add_http_outgoing_handler_to_linker<T>(
    linker: &mut wasmtime::component::Linker<T>,
    host_getter: fn(&mut T) -> &mut HttpHostImpl,
) -> anyhow::Result<()>
where
    T: 'static,
{
    http_tool::moltis::tool::outgoing_handler::add_to_linker::<
        T,
        wasmtime::component::HasSelf<HttpHostImpl>,
    >(linker, host_getter)
    .context("failed to add outgoing-handler to linker")?;
    Ok(())
}

#[cfg(feature = "wasm")]
#[must_use]
pub fn marshal_tool_result(value: PureToolValue) -> serde_json::Value {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(all(test, feature = "wasm"))]
mod tests {

    #[test]
    fn marshal_tool_result_text() {
    ...
}

    #[test]
    fn marshal_tool_result_number() {
    ...
}

    #[test]
    fn marshal_tool_result_integer() {
    ...
}

    #[test]
    fn marshal_tool_result_boolean() {
    ...
}

    #[test]
    fn marshal_tool_result_json() {
    ...
}

    fn spawn_http_server(body: &'static [u8], delay: Option<Duration>) -> (String, JoinHandle<()>) {
    ...
}

    fn request_for_url(url: String) -> HttpRequest {
    ...
}

    #[test]
    fn http_host_blocks_private_address_without_allowlist() {
    ...
}

    #[test]
    fn http_host_enforces_max_response_bytes() {
    ...
}

    #[test]
    fn http_host_maps_timeout_errors() {
    ...
}

    #[tokio::test(flavor = "multi_thread")]
    async fn http_host_new_inside_tokio_runtime() {
    ...
}

    /// Spawn a tiny HTTP server that echoes back all request headers as the
    /// response body (one `name: value` per line).
    fn spawn_echo_headers_server() -> (String, JoinHandle<()>) {
    ...
}

    fn host_with_allowlist_and_secrets(
        domain_allowlist: Option<Vec<String>>,
        secret_headers: HashMap<String, Vec<(String, String)>>,
    ) -> HttpHostImpl {
    ...
}

    #[test]
    fn http_host_injects_secret_headers() {
    ...
}

    #[test]
    fn http_host_secret_headers_override_guest_headers() {
    ...
}

    #[test]
    fn http_host_domain_allowlist_blocks_disallowed_host() {
    ...
}

    #[test]
    fn http_host_rejects_non_http_scheme() {
    ...
}

    #[test]
    fn http_host_rejects_invalid_method() {
    ...
}
}
