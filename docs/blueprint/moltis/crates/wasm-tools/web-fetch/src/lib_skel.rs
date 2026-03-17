// Pure functions are used by the WASM Guest impl; allow dead_code on non-wasm targets.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code, unused_imports))]

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

#[cfg(target_arch = "wasm32")]
use url::Url;

const DEFAULT_MAX_CHARS: usize = 50_000;
const DEFAULT_MAX_REDIRECTS: u8 = 5;
const DEFAULT_TIMEOUT_MS: u32 = 10_000;
const DEFAULT_MAX_RESPONSE_BYTES: u64 = 2_000_000;

#[cfg(target_arch = "wasm32")]
struct WebFetchWasm;

#[cfg(target_arch = "wasm32")]
impl Guest for WebFetchWasm {
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

#[cfg(target_arch = "wasm32")]
fn fetch_with_redirects(
    url_input: &str,
    extract_mode: &str,
    max_chars: usize,
    accept_language: Option<&str>,
) -> Result<Value, ToolError> {
    ...
}

#[cfg(target_arch = "wasm32")]
fn map_http_error(error: HttpError) -> ToolError {
    ...
}

fn header_value(headers: &[(String, String)], name: &str) -> Option<String> {
    ...
}

fn extract_content(body: &str, content_type: &str, requested_mode: &str) -> (String, String) {
    ...
}

fn html_to_text(html: &str) -> String {
    ...
}

fn truncate_at_char_boundary(s: &str, max: usize) -> String {
    ...
}

#[cfg(target_arch = "wasm32")]
export!(WebFetchWasm);

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn strips_script_content() {
    ...
}

    #[test]
    fn strips_style_content() {
    ...
}

    #[test]
    fn collapses_whitespace() {
    ...
}

    #[test]
    fn empty_html() {
    ...
}

    #[test]
    fn nested_tags() {
    ...
}

    // --- extract_content ---

    #[test]
    fn json_content_type_prettifies() {
    ...
}

    #[test]
    fn invalid_json_falls_back_to_text() {
    ...
}

    #[test]
    fn plain_text_passthrough() {
    ...
}

    #[test]
    fn html_markdown_mode() {
    ...
}

    #[test]
    fn html_text_mode() {
    ...
}

    #[test]
    fn html_empty_mode_defaults_to_markdown() {
    ...
}

    #[test]
    fn unknown_content_type_treated_as_text() {
    ...
}

    // --- truncate_at_char_boundary ---

    #[test]
    fn no_truncation_needed() {
    ...
}

    #[test]
    fn truncates_ascii() {
    ...
}

    #[test]
    fn truncates_at_valid_utf8_boundary() {
    ...
}

    #[test]
    fn truncate_multibyte_backs_up() {
    ...
}

    // --- header_value ---

    #[test]
    fn finds_header_case_insensitive() {
    ...
}

    #[test]
    fn missing_header_returns_none() {
    ...
}
}
