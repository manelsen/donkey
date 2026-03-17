//! iCalendar build/parse helpers using the `icalendar` crate.

use {
    anyhow::{Result, anyhow},
    icalendar::{Calendar, Component, Event, EventLike},
};

use crate::types::{EventSummary, NewEvent, UpdateEvent};

/// Build a VCALENDAR string containing a single VEVENT from the given parameters.
#[must_use]
pub fn build_vevent(event: &NewEvent, uid: &str) -> String {
    ...
}

/// Parse raw iCalendar data and extract event summaries.
pub fn parse_events(ical_data: &str, href: &str, etag: &str) -> Result<Vec<EventSummary>> {
    ...
}

/// Merge updates into an existing iCalendar string, preserving unmodified properties.
pub fn merge_updates(existing: &str, updates: &UpdateEvent) -> Result<String> {
    ...
}

/// Format a date/time string as iCalendar DATETIME (basic format).
/// Accepts ISO 8601 (`2025-06-15T10:00:00`) and converts to `20250615T100000`.
fn format_datetime(dt: &str) -> String {
    ...
}

/// Extract a date/time property and normalise to ISO 8601 for display.
fn extract_datetime(vevent: &Event, prop_name: &str) -> Option<String> {
    ...
}

/// Convert basic iCalendar datetime (20250615T100000) to ISO 8601 (2025-06-15T10:00:00).
fn normalise_datetime(raw: &str) -> String {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn build_vevent_all_day() {
    ...
}

    #[test]
    fn parse_events_roundtrip() {
    ...
}

    #[test]
    fn normalise_datetime_basic_to_iso() {
    ...
}

    #[test]
    fn normalise_datetime_date_only() {
    ...
}

    #[test]
    fn format_datetime_iso_to_basic() {
    ...
}

    #[test]
    fn format_datetime_already_basic() {
    ...
}

    #[test]
    fn merge_updates_changes_summary() {
    ...
}
}
