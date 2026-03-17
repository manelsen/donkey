use std::{collections::HashMap, str::FromStr};

use {
    reqwest::header::{HeaderMap, HeaderName, HeaderValue},
    secrecy::{ExposeSecret, Secret},
    url::Url,
};

use crate::{
    error::{Context, Error, Result},
    registry::McpServerConfig,
};

const REDACTED_QUERY_VALUE: &str = "[REDACTED]";
const REDACTED_USERINFO: &str = "redacted";
const INVALID_REMOTE_URL: &str = "[invalid remote URL]";

#[derive(Clone)]
pub struct ResolvedRemoteConfig {
    ...
}

impl ResolvedRemoteConfig {
    pub fn from_server_config(
        config: &McpServerConfig,
        env_overrides: &HashMap<String, String>,
    ) -> Result<Self> {

    pub fn request_url(&self) -> &str {
    ...
}

    pub fn display_url(&self) -> &str {
    ...
}

    pub fn headers(&self) -> &HeaderMap {
    ...
}
}

pub fn header_names(headers: &HashMap<String, Secret<String>>) -> Vec<String> {
    ...
}

pub fn sanitize_url_for_display(raw_url: &str) -> String {
    ...
}

pub fn sanitize_reqwest_error(err: reqwest::Error) -> reqwest::Error {
    ...
}

pub fn substitute_env_placeholders(input: &str, env_overrides: &HashMap<String, String>) -> String {
    ...
}

fn build_header_map(
    headers: &HashMap<String, Secret<String>>,
    env_overrides: &HashMap<String, String>,
) -> Result<HeaderMap> {
    ...
}

fn lookup_env(name: &str, env_overrides: &HashMap<String, String>) -> Option<String> {
    ...
}

fn is_entire_env_placeholder_syntax(value: &str) -> bool {
    ...
}

fn decode_display_escapes(value: &str) -> String {
    ...
}

fn is_env_ident_start(ch: char) -> bool {
    ...
}

fn is_env_ident_continue(ch: char) -> bool {
    ...
}

fn is_reserved_header(name: &str) -> bool {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn sanitize_url_for_display_redacts_query_values() {
    ...
}

    #[test]
    fn sanitize_url_for_display_preserves_placeholders() {
    ...
}

    #[test]
    fn sanitize_url_for_display_redacts_mixed_placeholder_values() {
    ...
}

    #[test]
    fn substitute_env_placeholders_ignores_process_env() {
    ...
}

    #[test]
    fn substitute_env_placeholders_preserves_utf8_segments() {
    ...
}

    #[test]
    fn build_header_map_rejects_case_insensitive_duplicates() {
    ...
}
}
