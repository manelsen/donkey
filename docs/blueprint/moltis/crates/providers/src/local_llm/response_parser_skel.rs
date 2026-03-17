//! Response parsing for local LLM backends.
//!
//! Different backends and models may output responses in different formats.
//! This module provides a trait-based approach to parse raw output into
//! structured responses, making it easy to add new parsers without modifying
//! existing code.

/// Parsed response from an LLM backend.
#[derive(Debug, Clone, Default)]
pub struct ParsedResponse {
    ...
}

/// Trait for parsing raw LLM output into structured responses.
///
/// Implement this trait for different output formats (JSON, CLI decorators, etc.).
pub trait ResponseParser: Send + Sync {
    /// Parse raw output into a structured response.
    fn parse(&self, raw: &str) -> ParsedResponse;

    /// Human-readable name for this parser (for logging/debugging).
    fn name(&self) -> &'static str;
}

// ── JSON Response Parser ─────────────────────────────────────────────────────

/// Parser for JSON-formatted responses from Python API.
///
/// Expects format: ` {
    ...
}