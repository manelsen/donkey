//! CalDAV client trait and `libdav`-backed implementation.

use std::sync::Arc;

use {
    anyhow::{Result, anyhow},
    async_trait::async_trait,
    secrecy::{ExposeSecret, Secret},
};

use crate::types::{
    CalendarInfo, CreatedEvent, EventSummary, NewEvent, TimeRange, UpdateEvent, UpdatedEvent,
};

/// Trait for CalDAV server interactions.
///
/// This allows mocking in tests without a real server.
#[async_trait]
pub trait CalDavClient: Send + Sync {
    /// Discover calendars available on this account.
    async fn list_calendars(&self) -> Result<Vec<CalendarInfo>>;

    /// List events in a calendar, optionally filtered by time range.
    async fn list_events(
        &self,
        calendar_href: &str,
        range: Option<TimeRange>,
    ) -> Result<Vec<EventSummary>>;

    /// Create a new event in the given calendar.
    async fn create_event(&self, calendar_href: &str, event: NewEvent) -> Result<CreatedEvent>;

    /// Update an existing event.
    async fn update_event(
        &self,
        href: &str,
        etag: &str,
        updates: UpdateEvent,
    ) -> Result<UpdatedEvent>;

    /// Delete an event.
    async fn delete_event(&self, href: &str, etag: &str) -> Result<()>;
}

/// `libdav`-backed CalDAV client using hyper + tower for HTTP.
pub struct LibDavCalDavClient {
    ...
}

/// Type alias for the libdav HTTPS connector stack.
type HyperHttpsClient = hyper_util::client::legacy::Client<
    hyper_rustls::HttpsConnector<hyper_util::client::legacy::connect::HttpConnector>,
    String,
>;

impl LibDavCalDavClient {
    /// Connect to a CalDAV server.
    ///
    /// Uses service discovery to locate the CalDAV context path.
    pub async fn connect(
        base_url: &str,
        username: &str,
        password: &Secret<String>,
    ) -> Result<Self> {

    /// Find calendar home set URLs for the current user.
    async fn find_calendar_homes(&self) -> Result<Vec<http::Uri>> {
    ...
}
}

#[async_trait]
impl CalDavClient for LibDavCalDavClient {
    async fn list_calendars(&self) -> Result<Vec<CalendarInfo>> {

    async fn list_events(
        &self,
        calendar_href: &str,
        _range: Option<TimeRange>,
    ) -> Result<Vec<EventSummary>> {
    ...
}

    async fn create_event(&self, calendar_href: &str, event: NewEvent) -> Result<CreatedEvent> {
    ...
}

    async fn update_event(
        &self,
        href: &str,
        etag: &str,
        updates: UpdateEvent,
    ) -> Result<UpdatedEvent> {
    ...
}

    async fn delete_event(&self, href: &str, etag: &str) -> Result<()> {
    ...
}
}

/// Thread-safe shared CalDAV client.
pub type SharedCalDavClient = Arc<dyn CalDavClient>;
