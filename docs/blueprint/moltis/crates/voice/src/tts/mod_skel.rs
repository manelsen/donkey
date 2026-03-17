//! Text-to-Speech provider abstraction and implementations.

mod coqui;
mod elevenlabs;
mod google;
mod openai;
mod piper;

pub use {
    coqui::CoquiTts, elevenlabs::ElevenLabsTts, google::GoogleTts, openai::OpenAiTts,
    piper::PiperTts,
};

use {
    anyhow::Result,
    async_trait::async_trait,
    bytes::Bytes,
    serde::{Deserialize, Serialize},
    std::borrow::Cow,
};

/// A voice available from a TTS provider.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Voice {
    ...
}

/// Audio output format.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AudioFormat {
    ...
}

impl AudioFormat {
    /// MIME type for this format.
    #[must_use]
    pub fn mime_type(&self) -> &'static str {

    /// File extension for this format.
    #[must_use]
    pub fn extension(&self) -> &'static str {
    ...
}

    /// Parse from a MIME content-type string (e.g. `"audio/webm"`, `"audio/webm;codecs=opus"`).
    #[must_use]
    pub fn from_content_type(ct: &str) -> Option<Self> {
    ...
}

    /// Parse from a short format name (e.g. `"webm"`, `"opus"`, `"ogg"`, `"mp3"`).
    #[must_use]
    pub fn from_short_name(name: &str) -> Self {
    ...
}
}

/// Request to synthesize speech from text.
#[derive(Debug, Clone, Default)]
pub struct SynthesizeRequest {
    ...
}

/// Audio output from TTS synthesis.
#[derive(Debug, Clone)]
pub struct AudioOutput {
    ...
}

/// Text-to-Speech provider trait.
///
/// Implementations provide speech synthesis from text using various services.
#[async_trait]
pub trait TtsProvider: Send + Sync {
    /// Provider identifier (e.g., "elevenlabs", "openai").
    fn id(&self) -> &'static str;

    /// Human-readable provider name.
    fn name(&self) -> &'static str;

    /// Check if the provider is configured and ready.
    fn is_configured(&self) -> bool;

    /// Whether this provider supports SSML tags natively.
    ///
    /// Providers that return `true` will receive SSML-tagged text as-is.
    /// Providers that return `false` will have SSML tags stripped before
    /// synthesis (handled centrally in the gateway's `convert()` handler).
    fn supports_ssml(&self) -> bool {
    ...
}

    /// List available voices from this provider.
    async fn voices(&self) -> Result<Vec<Voice>>;

    /// Convert text to speech.
    async fn synthesize(&self, request: SynthesizeRequest) -> Result<AudioOutput>;
}

/// Check whether text contains SSML tags (currently `<break`).
#[must_use]
pub fn contains_ssml(text: &str) -> bool {
    ...
}

/// Strip SSML tags (`<break .../>`) so non-SSML providers don't speak them
/// literally. Returns the input unchanged (no allocation) when no tags are
/// present.
#[must_use]
pub fn strip_ssml_tags(text: &str) -> Cow<'_, str> {
    ...
}

/// Sanitize LLM output for text-to-speech consumption.
///
/// Strips markdown formatting, raw URLs, code fences, and other visual syntax
/// that TTS engines would read literally. Returns `Cow::Borrowed` when the
/// input needs no changes (zero-alloc fast path).
///
/// Processing order:
/// 1. Remove fenced code blocks (``` ... ```)
/// 2. Remove URLs (`https?://…`)
/// 3. Strip markdown headers (`# `, `## `, etc.)
/// 4. Strip bold/italic markers (`**`, `__`, word-boundary `*`/`_`)
/// 5. Strip inline code backticks
/// 6. Strip bullet/list prefixes (`- `, `* `, `1. `)
/// 7. Collapse runs of whitespace / blank lines
/// 8. Strip SSML tags (via [`strip_ssml_tags`])
#[must_use]
pub fn sanitize_text_for_tts(text: &str) -> Cow<'_, str> {
    ...
}

/// Quick check for whether the text contains any markers we strip.
fn needs_sanitization(text: &str) -> bool {
    ...
}

/// Check if the text contains an ordered list pattern (`\n1. `, `\n2. `, etc.).
fn has_ordered_list(text: &str) -> bool {
    ...
}

/// Remove fenced code blocks (` ``` ... ``` `).
fn remove_code_fences(text: &str) -> String {
    ...
}

/// Remove markdown table blocks from text. A table block is a run of
/// consecutive lines containing pipe (`|`) column separators that includes
/// a separator row (`|---|` or `---+---`). Entire tables are removed because
/// pipe characters and alignment dashes are meaningless when read aloud.
fn remove_tables(text: &str) -> String {
    ...
}

/// Check if a line looks like a table row (contains `|` as column separator).
fn is_tts_table_line(line: &str) -> bool {
    ...
}

/// Check if a line is a table separator row (`|---|` or `---+---`).
fn is_tts_separator_row(line: &str) -> bool {
    ...
}

/// Strip leading `#` characters (markdown headers) from a line.
fn strip_leading_hashes(line: &str) -> &str {
    ...
}

/// Strip bullet/list prefixes from a line start.
fn strip_bullet_prefix(line: &str) -> &str {
    ...
}

/// Remove URLs matching `https?://\S+`.
fn remove_urls(text: &str) -> String {
    ...
}

/// Strip bold/italic markers (`**`, `__`, and word-boundary `*`/`_`).
///
/// Preserves contractions like "don't" by only stripping `_` at word boundaries
/// (i.e. preceded/followed by whitespace or at string boundaries).
fn strip_bold_italic(text: &str) -> String {
    ...
}

/// Collapse runs of multiple blank lines into a single newline.
fn collapse_whitespace(text: &str) -> String {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_sanitize_strips_urls() {
    ...
}

    #[test]
    fn test_sanitize_strips_http_urls() {
    ...
}

    #[test]
    fn test_sanitize_strips_markdown_headers() {
    ...
}

    #[test]
    fn test_sanitize_strips_code_fences() {
    ...
}

    #[test]
    fn test_sanitize_strips_inline_code() {
    ...
}

    #[test]
    fn test_sanitize_strips_bold_italic() {
    ...
}

    #[test]
    fn test_sanitize_strips_underscore_bold_italic() {
    ...
}

    #[test]
    fn test_sanitize_strips_bullet_lists() {
    ...
}

    #[test]
    fn test_sanitize_strips_ordered_lists() {
    ...
}

    #[test]
    fn test_sanitize_preserves_contractions() {
    ...
}

    #[test]
    fn test_sanitize_realistic_llm_output() {
    ...
}

    #[test]
    fn test_sanitize_strips_ssml_tags() {
    ...
}

    #[test]
    fn test_sanitize_strips_pipe_table() {
    ...
}

    #[test]
    fn test_sanitize_strips_plus_separator_table() {
    ...
}

    #[test]
    fn test_sanitize_keeps_single_pipe_in_prose() {
    ...
}

    #[test]
    fn test_audio_format_mime_type() {
    ...
}

    #[test]
    fn test_audio_format_extension() {
    ...
}

    #[test]
    fn test_audio_format_from_content_type() {
    ...
}

    #[test]
    fn test_audio_format_from_short_name() {
    ...
}

    #[test]
    fn test_synthesize_request_default() {
    ...
}

    #[test]
    fn test_contains_ssml() {
    ...
}

    #[test]
    fn test_strip_ssml_tags_no_tags() {
    ...
}

    #[test]
    fn test_strip_ssml_tags_self_closing() {
    ...
}

    #[test]
    fn test_strip_ssml_tags_multiple() {
    ...
}

    #[test]
    fn test_strip_ssml_tags_at_boundaries() {
    ...
}

    #[test]
    fn test_strip_ssml_tags_malformed() {
    ...
}
}
