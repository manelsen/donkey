// Pure functions are used by the WASM Guest impl; allow dead_code on non-wasm targets.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

#[cfg(target_arch = "wasm32")]
wit_bindgen::generate!({
    path: "../../../wit",
    world: "http-tool",
});

#[cfg(target_arch = "wasm32")]
use crate::moltis::tool::{
    outgoing_handler::{self, HttpError, HttpRequest},
    types::{ToolError, ToolValue},
};

use serde_json::{Value, json};

const DEFAULT_TIMEOUT_MS: u32 = 12_000;
const DEFAULT_MAX_RESPONSE_BYTES: u64 = 2_000_000;
const DEFAULT_RESULT_COUNT: u8 = 5;

#[cfg(target_arch = "wasm32")]
struct WebSearchWasm;

#[cfg(target_arch = "wasm32")]
impl Guest for WebSearchWasm {
    fn name() -> String {

    fn description() -> String {
    ...
}

    fn parameters_schema() -> String {
    ...
}

    fn execute(params_json: String) -> ToolResult {
    ...
}
}

#[cfg(target_arch = "wasm32")]
fn execute_impl(params_json: &str) -> Result<Value, ToolError> {
    ...
}

fn parse_brave_results(body: &Value) -> Vec<Value> {
    ...
}

#[cfg(target_arch = "wasm32")]
fn map_http_error(error: HttpError) -> ToolError {
    ...
}

fn url_encode(s: &str) -> String {
    ...
}

#[cfg(target_arch = "wasm32")]
export!(WebSearchWasm);

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn preserves_unreserved_chars() {
    ...
}

    #[test]
    fn encodes_special_chars() {
    ...
}

    #[test]
    fn encodes_unicode() {
    ...
}

    #[test]
    fn empty_string() {
    ...
}

    // --- parse_brave_results ---

    #[test]
    fn parses_normal_results() {
    ...
}

    #[test]
    fn skips_results_missing_title() {
    ...
}

    #[test]
    fn skips_results_missing_url() {
    ...
}

    #[test]
    fn skips_empty_title_and_url() {
    ...
}

    #[test]
    fn handles_missing_web_key() {
    ...
}

    #[test]
    fn handles_empty_results_array() {
    ...
}

    #[test]
    fn description_defaults_to_empty() {
    ...
}
}
