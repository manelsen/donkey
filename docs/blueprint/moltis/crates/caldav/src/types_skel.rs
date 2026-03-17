//! Typed structs for CalDAV operations.

use serde::{Deserialize, Serialize};

/// Information about a discovered calendar collection.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CalendarInfo {
    ...
}

/// Summary of a single calendar event (returned by `list_events`).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventSummary {
    ...
}

/// Parameters for creating a new event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct NewEvent {
    ...
}

/// Fields that can be updated on an existing event.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct UpdateEvent {
    ...
}

/// Result of a successful event creation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CreatedEvent {
    ...
}

/// Result of a successful event update.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct UpdatedEvent {
    ...
}

/// Time range filter for listing events.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeRange {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn new_event_serde_roundtrip() {
    ...
}

    #[test]
    fn event_summary_serde_roundtrip() {
    ...
}

    #[test]
    fn update_event_defaults_all_none() {
    ...
}
}
