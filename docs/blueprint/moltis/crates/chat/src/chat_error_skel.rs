//! Structured error parsing for chat error messages.
//!
//! Converts raw error strings from agent runners / LLM providers into
//! structured JSON payloads that the frontend can render directly.

use serde_json::Value;

/// Parse a raw error string into a structured error object with `type`, `icon`,
/// `title`, `detail`, and optionally `provider`, `resetsAt`, and
/// `retryAfterMs` fields.
pub fn parse_chat_error(raw: &str, provider_name: Option<&str>) -> Value {
    ...
}

fn try_parse_known_error(raw: &str) -> Value {
    ...
}