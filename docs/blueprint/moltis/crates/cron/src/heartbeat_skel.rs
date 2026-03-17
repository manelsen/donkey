//! Heartbeat logic: token stripping, empty-content detection, active-hours check.

use chrono::{Local, NaiveTime, Timelike, Utc};

/// The sentinel token an LLM returns when nothing noteworthy is happening.
pub const HEARTBEAT_OK: &str = "HEARTBEAT_OK";

/// Default heartbeat interval in milliseconds (30 minutes).
pub const DEFAULT_INTERVAL_MS: u64 = 30 * 60 * 1000;

/// Default maximum characters for an acknowledgment reply.
pub const DEFAULT_ACK_MAX_CHARS: usize = 300;

/// Default heartbeat prompt sent to the LLM.
pub const DEFAULT_PROMPT: &str = "\
You are performing a periodic heartbeat check. Review any pending items \
(inbox, calendar, reminders, scheduled tasks) and determine if anything \
needs the user's attention right now.\n\n\
- If nothing requires attention, reply with exactly: HEARTBEAT_OK\n\
- If something needs attention, describe it concisely (under 300 characters).\n\
Do NOT wrap HEARTBEAT_OK in markdown formatting.";

/// Result of stripping the `HEARTBEAT_OK` token from an LLM reply.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StripResult {
    ...
}

/// How aggressively to strip the heartbeat token.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StripMode {
    ...
}

/// Source of the effective heartbeat prompt.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HeartbeatPromptSource {
    ...
}

impl HeartbeatPromptSource {
    #[must_use]
    pub fn as_str(self) -> &'static str {
}

/// Strip `HEARTBEAT_OK` from `text`, handling common LLM formatting wrappers
/// like `**HEARTBEAT_OK**` and `<b>HEARTBEAT_OK</b>`.
///
/// Returns a [`StripResult`] indicating whether the reply should be suppressed.
pub fn strip_heartbeat_token(text: &str, mode: StripMode, max_ack_chars: usize) -> StripResult {
    ...
}

/// Returns `true` if a HEARTBEAT.md file's content is effectively empty
/// (only headers, blank lines, and empty list items).
pub fn is_heartbeat_content_empty(content: &str) -> bool {
    ...
}

/// Check whether the current time falls within the active hours window.
///
/// Handles overnight windows (e.g. start=22:00, end=06:00).
/// If timezone is "local" or empty, uses the system local time.
pub fn is_within_active_hours(start: &str, end: &str, timezone: &str) -> bool {
    ...
}

/// Resolve the heartbeat prompt with precedence:
///
/// 1. Explicit config prompt (`custom`)
/// 2. `HEARTBEAT.md` content (`heartbeat_md`)
/// 3. Built-in default prompt
pub fn resolve_heartbeat_prompt(
    custom: Option<&str>,
    heartbeat_md: Option<&str>,
) -> (String, HeartbeatPromptSource) {
    ...
}

/// Parse a human-friendly interval string like "30m", "1h", "90s" into milliseconds.
/// Returns `None` for unparseable input.
pub fn parse_interval_ms(s: &str) -> Option<u64> {
    ...
}

// ── Event enrichment ─────────────────────────────────────────────────────────

/// Prefix prepended to the heartbeat prompt when system events are pending.
pub const EVENTS_PROMPT_PREFIX: &str = "Events occurred since your last check. \
    Review them and relay anything noteworthy to the user.\n\n";

/// Build a heartbeat prompt that incorporates pending system events.
///
/// If `events` is empty, returns `base_prompt` unchanged.
#[must_use]
pub fn build_event_enriched_prompt(
    events: &[crate::system_events::SystemEvent],
    base_prompt: &str,
) -> String {
    ...
}

// ── Helpers ──────────────────────────────────────────────────────────────────

fn unwrap_bold(s: &str) -> &str {
    ...
}

fn parse_hhmm(s: &str) -> Option<NaiveTime> {
    ...
}

fn current_minutes(timezone: &str) -> u32 {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn strip_bold_wrapped() {
    ...
}

    #[test]
    fn strip_html_bold_wrapped() {
    ...
}

    #[test]
    fn strip_with_whitespace() {
    ...
}

    #[test]
    fn strip_exact_with_extra_text() {
    ...
}

    #[test]
    fn strip_trim_removes_token() {
    ...
}

    #[test]
    fn strip_trim_only_token() {
    ...
}

    // ── is_heartbeat_content_empty ───────────────────────────────────────

    #[test]
    fn empty_content() {
    ...
}

    #[test]
    fn headers_only() {
    ...
}

    #[test]
    fn has_content() {
    ...
}

    // ── is_within_active_hours ───────────────────────────────────────────

    #[test]
    fn invalid_time_always_active() {
    ...
}

    #[test]
    fn active_hours_normal_window() {
    ...
}

    #[test]
    fn active_hours_overnight_window() {
    ...
}

    // ── resolve_heartbeat_prompt ─────────────────────────────────────────

    #[test]
    fn default_prompt_when_none() {
    ...
}

    #[test]
    fn default_prompt_when_empty() {
    ...
}

    #[test]
    fn custom_prompt() {
    ...
}

    #[test]
    fn heartbeat_md_used_when_config_missing() {
    ...
}

    #[test]
    fn config_overrides_heartbeat_md() {
    ...
}

    #[test]
    fn prompt_source_as_str_values() {
    ...
}

    // ── parse_interval_ms ────────────────────────────────────────────────

    #[test]
    fn parse_minutes() {
    ...
}

    #[test]
    fn parse_hours() {
    ...
}

    #[test]
    fn parse_seconds() {
    ...
}

    #[test]
    fn parse_raw_ms() {
    ...
}

    #[test]
    fn parse_empty() {
    ...
}

    #[test]
    fn parse_invalid() {
    ...
}

    // ── build_event_enriched_prompt ──────────────────────────────────────

    #[test]
    fn enriched_prompt_with_no_events() {
    ...
}

    #[test]
    fn enriched_prompt_with_events() {
    ...
}
}
