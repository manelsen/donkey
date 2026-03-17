//! `get_user_location` tool — requests the user's geographic coordinates via
//! the browser Geolocation API.
//!
//! The tool checks for a cached location first (fast path), then asks the
//! gateway to send a WebSocket event to the connected browser client.  The
//! browser shows its native permission popup and returns the coordinates (or
//! an error) via an RPC response.

use std::sync::Arc;

use {
    async_trait::async_trait,
    moltis_config::GeoLocation,
    serde::{Deserialize, Serialize},
    tracing::warn,
};

use crate::{Result, error::Error};

// ── Precision ───────────────────────────────────────────────────────────────

/// How accurate the location fix should be.
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum LocationPrecision {
    ...
}

// ── Types ────────────────────────────────────────────────────────────────────

/// Location coordinates returned by the browser Geolocation API.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BrowserLocation {
    ...
}

/// Reason the location could not be obtained.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum LocationError {
    ...
}

impl std::fmt::Display for LocationError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
}

/// Result from the browser geolocation request.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LocationResult {
    ...
}

// ── Trait ─────────────────────────────────────────────────────────────────────

/// Abstraction for requesting location from a connected browser client.
///
/// Implemented by the gateway layer and injected into [`LocationTool`] at
/// construction time.  This avoids a circular dependency between `crates/tools`
/// and `crates/gateway`.
#[async_trait]
pub trait LocationRequester: Send + Sync {
    /// Request location from the client identified by `conn_id`.
    ///
    /// The implementation creates a pending‐invoke, sends a WebSocket event to
    /// the browser, and awaits the response with a timeout.
    ///
    /// `precision` controls the browser's `enableHighAccuracy` and cache age.
    async fn request_location(
        &self,
        conn_id: &str,
        precision: LocationPrecision,
    ) -> Result<LocationResult>;

    /// Return a previously cached location (from `USER.md` or in-memory cache).
    fn cached_location(&self) -> Option<GeoLocation>;

    /// Request location from a channel user (e.g. Telegram).
    ///
    /// Sends a message asking the user to share their location via the channel's
    /// native location-sharing feature, then waits for the result.
    async fn request_channel_location(&self, _session_key: &str) -> Result<LocationResult> {
    ...
}
}

// ── Reverse geocoding ────────────────────────────────────────────────────────

/// Nominatim reverse-geocode response (subset of fields we care about).
#[derive(Debug, Deserialize)]
struct NominatimResponse {
    ...
}

/// Address breakdown from Nominatim.
#[derive(Debug, Deserialize)]
struct NominatimAddress {
    ...
}

/// Full + short place name pair from reverse geocoding.
struct PlaceName {
    ...
}

/// Resolve lat/lon to a human-readable place name via Nominatim (OpenStreetMap).
///
/// Returns `None` on any failure (network, parse, timeout) so the caller can
/// fall back to raw coordinates.
async fn reverse_geocode(lat: f64, lon: f64) -> Option<PlaceName> {
    ...
}

/// Inner implementation that accepts a `reqwest::Client` for testability.
async fn reverse_geocode_with_client(
    client: &reqwest::Client,
    lat: f64,
    lon: f64,
) -> Option<PlaceName> {
    ...
}

/// Build a concise place string from Nominatim address components.
///
/// Prefers: neighbourhood/suburb, city/town/village, state, country_code.
fn format_address(addr: &NominatimAddress) -> String {
    ...
}

/// Return the most local place component — suitable for voice/TTS.
///
/// Prefers neighbourhood/suburb, then city/town/village, then state.
fn format_address_short(addr: &NominatimAddress) -> String {
    ...
}

/// Set `place` and `place_short` on a JSON response object.
fn set_place_fields(resp: &mut serde_json::Value, place: Option<&PlaceName>) {
    ...
}

// ── Tool ──────────────────────────────────────────────────────────────────────

/// LLM-callable tool that requests the user's geographic coordinates.
pub struct LocationTool {
    ...
}

impl LocationTool {
    pub fn new(requester: Arc<dyn LocationRequester>) -> Self {
}

#[async_trait]
impl moltis_agents::tool_registry::AgentTool for LocationTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> serde_json::Value {
    ...
}

    async fn execute(&self, params: serde_json::Value) -> anyhow::Result<serde_json::Value> {
    ...
}
}

// ── Tests ─────────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
