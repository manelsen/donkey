use std::time::Duration;

#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct UpdateAvailability {
    ...
}

/// A channel entry in the releases manifest.
#[derive(Debug, Clone, serde::Deserialize)]
struct ReleaseChannel {
    ...
}

/// The `releases.json` manifest served at the configured URL.
#[derive(Debug, serde::Deserialize)]
struct ReleasesManifest {
    ...
}

pub const UPDATE_CHECK_INTERVAL: Duration = Duration::from_secs(60 * 60);

const DEFAULT_RELEASES_URL: &str = "https://www.moltis.org/releases.json";

/// Resolve the releases manifest URL from config, falling back to the default.
#[must_use]
pub fn resolve_releases_url(configured: Option<&str>) -> String {
    ...
}

/// Fetch update availability from the releases manifest.
///
/// Returns a default (no update) on any error — 404, parse failure, network
/// issues — so callers never have to handle errors.
pub async fn fetch_update_availability(
    client: &reqwest::Client,
    releases_url: &str,
    current_version: &str,
) -> UpdateAvailability {
    ...
}

async fn try_fetch_update(
    client: &reqwest::Client,
    releases_url: &str,
    current_version: &str,
) -> Result<UpdateAvailability, Box<dyn std::error::Error + Send + Sync>> {
    ...
}

fn update_from_release(
    tag_name: &str,
    release_url: Option<&str>,
    current: &str,
) -> UpdateAvailability {
    ...
}

fn is_pre_release(version: &str) -> bool {
    ...
}

/// Compare two version strings. Handles three cases:
/// 1. Both date-based (`YYYYMMDD.NN`) — compare as `(date, seq)` tuples.
/// 2. Both semver (`x.y.z`) — compare as `(major, minor, patch)` tuples.
/// 3. Mixed: any date-based version is considered newer than any semver version,
///    ensuring users on old semver builds see the update to the new scheme.
fn is_newer_version(latest: &str, current: &str) -> bool {
    ...
}

fn normalize_version(value: &str) -> String {
    ...
}

/// Parse a date-based version `YYYYMMDD.NN` into `(date, sequence)`.
fn parse_date_version(version: &str) -> Option<(u32, u32)> {
    ...
}

fn parse_semver_triplet(version: &str) -> Option<(u64, u64, u64)> {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn rejects_invalid_date_versions() {
    ...
}

    #[test]
    fn semver_not_confused_with_date() {
    ...
}

    // --- semver parsing ---

    #[test]
    fn parses_valid_semver() {
    ...
}

    #[test]
    fn rejects_date_version_as_semver() {
    ...
}

    // --- version comparison ---

    #[test]
    fn compares_semver_versions() {
    ...
}

    #[test]
    fn compares_date_versions() {
    ...
}

    #[test]
    fn date_version_newer_than_any_semver() {
    ...
}

    #[test]
    fn semver_not_newer_than_date_version() {
    ...
}

    // --- existing tests updated ---

    #[test]
    fn resolves_releases_url_with_config_override() {
    ...
}

    #[test]
    fn resolves_releases_url_default_when_missing_or_blank() {
    ...
}

    #[test]
    fn strips_pre_release_metadata_before_compare() {
    ...
}

    #[test]
    fn builds_update_payload_from_release() {
    ...
}

    #[test]
    fn builds_update_payload_date_to_date() {
    ...
}

    #[test]
    fn detects_pre_release_versions() {
    ...
}

    #[test]
    fn selects_channel_based_on_current_version() {
    ...
}
}
