//! JSON Schema cleaning and validation for LLM tool-calling compatibility.
//!
//! Different providers support different subsets of JSON Schema. This module
//! normalizes tool schemas to improve cross-provider compatibility while
//! preserving semantic intent.
//!
//! Operations:
//! 1. Removes unsupported keywords per provider strategy
//! 2. Resolves local `$ref` entries from `$defs` and `definitions`
//! 3. Flattens literal `anyOf` / `oneOf` unions into `enum`
//! 4. Strips nullable variants from unions and `type` arrays
//! 5. Converts `const` to single-value `enum`
//! 6. Detects circular references and stops recursion safely

const std = @import("std");

const log = std.log.scoped(.schema);

/// Schema cleaning strategies for different LLM providers.
pub const CleaningStrategy = enum {
    /// Gemini (Google AI / Vertex AI) — most restrictive.
    /// Anthropic Claude — moderately permissive.
    /// OpenAI GPT — most permissive.
    /// Conservative: remove only universally unsupported keywords.

/// Keywords that Gemini rejects for tool schemas.
    // Schema composition
    // Property constraints
    // String constraints
    // Number constraints
    // Array constraints
    // Object constraints
    // Non-standard

/// Keywords Anthropic doesn't handle (refs).

/// OpenAI is most permissive — no keywords removed.
const OPENAI_UNSUPPORTED_KEYWORDS = [_][]const u8{