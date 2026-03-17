/// Convert a subset of Markdown to Telegram-compatible HTML.
///
/// Telegram supports: `<b>`, `<i>`, `<code>`, `<pre>`, `<a href="">`,
/// `<s>` (strikethrough), `<u>` (underline).
///
/// Handles inline formatting (bold, italic, code, links, strikethrough)
/// and block-level markdown tables (rendered as aligned `<pre>` blocks
/// since Telegram does not support `<table>` HTML).
pub fn markdown_to_telegram_html(md: &str) -> String {
    ...
}

// ── Table detection & rendering ──────────────────────────────────────────

enum Segment {
    ...
}

/// Split markdown into alternating text and table segments.
fn split_table_segments(md: &str) -> Vec<Segment> {
    ...
}

fn flush_table_block<'a>(
    segments: &mut Vec<Segment>,
    text_lines: &mut Vec<&'a str>,
    table_lines: &mut Vec<&'a str>,
) {
    if table_lines.len() >= 2 && is_separator_row(table_lines[1]) {
        if !text_lines.is_empty() {
            segments.push(Segment::Text(text_lines.join("\n")));
            text_lines.clear();
        }
        segments.push(Segment::Table(
            table_lines.iter().map(|s| (*s).to_owned()).collect(),
        ));
    } else {
        text_lines.extend(table_lines.iter());
    }
    table_lines.clear();
}

fn is_table_line(trimmed: &str) -> bool {
    ...
}

/// Detect separator rows using `+` as intersection character (e.g. `---+---+---`).
fn is_plus_separator_row(trimmed: &str) -> bool {
    ...
}

fn is_separator_row(line: &str) -> bool {
    ...
}

fn parse_table_cells(line: &str) -> Vec<String> {
    ...
}

/// Maximum rendered table width (in characters) before switching from a
/// horizontal `<pre>` layout to a vertical card layout.  Telegram mobile
/// typically shows ~36 monospace characters per line inside `<pre>` blocks.
const MAX_TABLE_PRE_WIDTH: usize = 42;

fn render_table_pre(lines: &[String]) -> String {
    ...
}

/// Render a wide table in vertical card format for mobile-friendly display.
///
/// Each data row becomes a card: the first column value is the bold title,
/// remaining columns are listed as `Header: value` pairs.
fn render_table_vertical(rows: &[Vec<String>]) -> String {
    ...
}

// ── Inline markdown rendering ────────────────────────────────────────────

/// Render inline markdown constructs (bold, italic, code, links, etc.)
/// to Telegram-compatible HTML. HTML special chars are escaped first.
fn render_inline_markdown(md: &str) -> String {
    ...
}

/// Peek at the next `n` characters without consuming them.
fn peek_n(chars: &mut std::iter::Peekable<std::str::Chars<'_>>, n: usize) -> String {
    ...
}

/// Escape HTML special characters.
fn escape_html(text: &str) -> String {
    ...
}

/// Telegram message size limit.
pub const TELEGRAM_MAX_MESSAGE_LEN: usize = 4096;

/// Telegram caption size limit for media messages (voice, photo, document).
pub const TELEGRAM_CAPTION_LIMIT: usize = 1024;

#[must_use]
pub fn truncate_at_char_boundary(text: &str, max_len: usize) -> &str {
    ...
}

/// Split text into chunks that fit within Telegram's message limit.
/// Tries to split at newlines or spaces to avoid breaking words.
pub fn chunk_message(text: &str, max_len: usize) -> Vec<String> {
    ...
}

/// Split markdown into Telegram-safe HTML chunks that each fit `max_len`.
///
/// Unlike splitting rendered HTML directly, this chunks the markdown source and
/// renders each chunk independently so we don't cut through HTML tags.
pub fn chunk_markdown_html(markdown: &str, max_len: usize) -> Vec<String> {
    ...
}

fn best_markdown_split(markdown: &str, max_len: usize) -> usize {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn fenced_code_block() {
    ...
}

    #[test]
    fn link() {
    ...
}

    #[test]
    fn table_renders_as_pre_block() {
    ...
}

    #[test]
    fn table_columns_are_aligned() {
    ...
}

    #[test]
    fn table_between_text_preserves_context() {
    ...
}

    #[test]
    fn invalid_table_no_separator_passes_through() {
    ...
}

    #[test]
    fn table_escapes_html_in_cells() {
    ...
}

    #[test]
    fn table_single_column() {
    ...
}

    #[test]
    fn table_without_leading_pipes() {
    ...
}

    #[test]
    fn table_without_leading_pipes_preserves_context() {
    ...
}

    #[test]
    fn wide_table_uses_vertical_card_format() {
    ...
}

    #[test]
    fn wide_table_vertical_preserves_context() {
    ...
}

    #[test]
    fn narrow_table_still_uses_pre() {
    ...
}

    #[test]
    fn single_pipe_not_detected_as_table() {
    ...
}

    #[test]
    fn chunk_short_message() {
    ...
}

    #[test]
    fn chunk_at_newline() {
    ...
}

    #[test]
    fn chunk_at_space() {
    ...
}

    #[test]
    fn truncate_at_char_boundary_handles_utf8() {
    ...
}

    #[test]
    fn chunk_message_handles_utf8_boundary() {
    ...
}

    #[test]
    fn markdown_to_telegram_html_closes_unterminated_inline_code() {
    ...
}

    #[test]
    fn chunk_markdown_html_respects_limit() {
    ...
}

    #[test]
    fn chunk_markdown_html_handles_long_inline_code() {
    ...
}
}
