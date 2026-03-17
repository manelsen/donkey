//! `show_map` tool — displays a static map image with a clickable link to the
//! configured map provider.
//!
//! Composes a static map from OSM tiles (no API key required), draws marker
//! pins for one or more destinations and optionally the user's current
//! location, and returns clickable links so the user can open locations in
//! their preferred mapping application.

use std::io::Cursor;

use {
    async_trait::async_trait,
    base64::{Engine as _, engine::general_purpose::STANDARD as BASE64},
    image::{ImageFormat, RgbaImage, imageops},
    moltis_agents::tool_registry::AgentTool,
    serde::Deserialize,
    tracing::{debug, warn},
};

use crate::{Result, error::Error};

// ── Parameters ──────────────────────────────────────────────────────────────

#[derive(Debug, Deserialize)]
struct ShowMapPointParams {
    ...
}

#[derive(Debug, Deserialize)]
struct ShowMapParams {
    ...
}

#[derive(Debug, Clone)]
struct DestinationPoint {
    ...
}

fn validate_latitude(value: f64, field: &str) -> Result<()> {
    ...
}

fn validate_longitude(value: f64, field: &str) -> Result<()> {
    ...
}

fn normalize_destination_points(params: &ShowMapParams) -> Result<Vec<DestinationPoint>> {
    ...
}

// ── Map links ───────────────────────────────────────────────────────────────

/// Map provider used to generate outbound map links.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum MapProvider {
    ...
}

impl MapProvider {
    fn as_config_value(self) -> &'static str {
}

/// Build clickable map URLs for the selected mapping provider.
fn build_map_links(
    provider: MapProvider,
    lat: f64,
    lon: f64,
    zoom: u8,
    label: Option<&str>,
) -> serde_json::Value {
    ...
}

/// Minimal percent-encoding for URL query values.
fn urlencoded(s: &str) -> String {
    ...
}

const HEX_UPPER: &[u8; 16] = b"0123456789ABCDEF";

// ── OSM tile math ───────────────────────────────────────────────────────────

const TILE_SIZE: u32 = 256;

/// Convert lat/lon to fractional tile coordinates at a given zoom level.
fn lat_lon_to_tile(lat: f64, lon: f64, zoom: u8) -> (f64, f64) {
    ...
}

/// Convert lat/lon to normalized Web Mercator world coordinates [0, 1].
fn lat_lon_to_world(lat: f64, lon: f64) -> (f64, f64) {
    ...
}

/// Convert normalized Web Mercator world coordinates [0, 1] back to lat/lon.
fn world_to_lat_lon(x: f64, y: f64) -> (f64, f64) {
    ...
}

/// Find minimal wrapped x-span and center on a [0, 1) circle.
fn wrapped_span_and_center(values: &[f64]) -> Option<(f64, f64)> {
    ...
}

/// Compute the map center that keeps points tightly framed, including
/// international date-line crossings.
fn center_for_points(points: &[(f64, f64)]) -> Option<(f64, f64)> {
    ...
}

/// Choose a zoom level that fits all points within the given pixel dimensions,
/// with some padding so markers aren't at the very edge.
fn auto_zoom_points(points: &[(f64, f64)], width: u32, height: u32) -> u8 {
    ...
}

/// Choose a zoom level that fits two points (legacy helper kept for tests).
#[cfg(test)]
fn auto_zoom(lat1: f64, lon1: f64, lat2: f64, lon2: f64, width: u32, height: u32) -> u8 {
    ...
}

// ── Static map compositing ──────────────────────────────────────────────────

/// Marker to draw on the map.
struct Marker {
    ...
}

const MAP_WIDTH: u32 = 600;
const MAP_HEIGHT: u32 = 400;
const MARKER_RADIUS: i32 = 10;
const USER_MARKER_COLOR: [u8; 4] = [50, 120, 220, 255];
const DESTINATION_MARKER_COLORS: [[u8; 4]; 6] = [
    [220, 50, 50, 255],
    [217, 119, 6, 255],
    [5, 150, 105, 255],
    [124, 58, 237, 255],
    [14, 116, 144, 255],
    [185, 28, 28, 255],
];

/// Compose a static map from OSM tiles with markers.
///
/// Returns `Some(data_uri)` on success, `None` on failure (network errors,
/// tile decode errors). The caller degrades gracefully to links-only.
async fn compose_static_map(
    client: &reqwest::Client,
    center_lat: f64,
    center_lon: f64,
    zoom: u8,
    markers: &[Marker],
) -> Option<String> {
    ...
}

/// Fetch a single OSM tile and decode it as RGBA.
async fn fetch_tile(client: &reqwest::Client, url: &str) -> Option<RgbaImage> {
    ...
}

// ── ImageMagick fallback ────────────────────────────────────────────────────

/// Compose a static map using ImageMagick (`magick`) as a fallback when the
/// in-process tile compositing fails.
///
/// Builds a single `magick` pipeline that:
/// 1. Fetches tiles directly from URLs (ImageMagick's own HTTP client)
/// 2. Stitches rows with `+append`, then stacks with `-append`
/// 3. Crops to the target size
/// 4. Draws marker circles
/// 5. Outputs PNG to stdout
///
/// Returns `None` if `magick` is not available or the command fails.
async fn compose_static_map_magick(
    center_lat: f64,
    center_lon: f64,
    zoom: u8,
    markers: &[Marker],
) -> Option<String> {
    ...
}

/// Draw a filled circle marker with a dark border on the canvas.
fn draw_marker(canvas: &mut RgbaImage, cx: i32, cy: i32, radius: i32, color: [u8; 4]) {
    ...
}

// ── Tool ────────────────────────────────────────────────────────────────────

/// LLM-callable tool that shows a map image with links to mapping services.
pub struct ShowMapTool {
    ...
}

impl ShowMapTool {
    pub fn new() -> Self {

    pub fn with_provider(provider: MapProvider) -> Self {
    ...
}
}

impl Default for ShowMapTool {
    fn default() -> Self {
}

#[async_trait]
impl AgentTool for ShowMapTool {
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

// ── Tests ───────────────────────────────────────────────────────────────────

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn build_links_without_label() {
    ...
}

    #[test]
    fn build_links_special_chars_in_label() {
    ...
}

    #[test]
    fn urlencoded_basic() {
    ...
}

    #[test]
    fn tool_schema_is_valid() {
    ...
}

    #[tokio::test]
    async fn execute_validates_latitude_range() {
    ...
}

    #[tokio::test]
    async fn execute_validates_longitude_range() {
    ...
}

    #[tokio::test]
    async fn execute_validates_user_latitude_range() {
    ...
}

    #[tokio::test]
    async fn execute_validates_user_longitude_range() {
    ...
}

    #[tokio::test]
    async fn execute_clamps_zoom() {
    ...
}

    #[tokio::test]
    async fn execute_includes_label_in_result() {
    ...
}

    #[tokio::test]
    async fn execute_graceful_without_screenshot() {
    ...
}

    #[tokio::test]
    async fn execute_supports_points_input() {
    ...
}

    #[tokio::test]
    async fn execute_rejects_missing_destinations() {
    ...
}

    #[tokio::test]
    async fn execute_validates_points_latitude_range() {
    ...
}

    // ── Tile math tests ─────────────────────────────────────────────────────

    #[test]
    fn tile_coords_at_zoom_0() {
    ...
}

    #[test]
    fn tile_coords_known_location() {
    ...
}

    #[test]
    fn auto_zoom_nearby_points() {
    ...
}

    #[test]
    fn auto_zoom_distant_points() {
    ...
}

    #[test]
    fn auto_zoom_same_point() {
    ...
}

    #[test]
    fn auto_zoom_multiple_points() {
    ...
}

    #[test]
    fn center_for_points_handles_date_line() {
    ...
}

    // ── Marker drawing tests ────────────────────────────────────────────────

    #[test]
    fn draw_marker_center_pixel() {
    ...
}

    #[test]
    fn draw_marker_has_border() {
    ...
}

    #[test]
    fn draw_marker_edge_clipping() {
    ...
}

    // ── Mock tile fetch tests ───────────────────────────────────────────────

    #[tokio::test]
    async fn fetch_tile_with_mock() {
    ...
}

    #[tokio::test]
    async fn fetch_tile_server_error() {
    ...
}

    #[tokio::test]
    async fn compose_map_with_mock_tiles() {
    ...
}

    /// Test helper — like `compose_static_map` but with a configurable tile URL
    /// base for mock server testing.
    async fn compose_static_map_with_base_url(
        client: &reqwest::Client,
        base_url: &str,
        center_lat: f64,
        center_lon: f64,
        zoom: u8,
        markers: &[Marker],
    ) -> Option<String> {
    ...
}

    // ── ImageMagick fallback tests ──────────────────────────────────────────

    #[tokio::test]
    async fn magick_fallback_produces_image() {
    ...
}
}
