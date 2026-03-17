//! Provider-specific CalDAV service discovery.
//!
//! Maps well-known providers to their CalDAV endpoints.

/// Well-known CalDAV base URL for Fastmail.
pub const FASTMAIL_CALDAV_URL: &str = "https://caldav.fastmail.com";

/// Well-known CalDAV base URL for iCloud.
/// Requires an app-specific password.
pub const ICLOUD_CALDAV_URL: &str = "https://caldav.icloud.com";

/// Resolve the CalDAV base URL for a given provider.
///
/// If `provider` is `None` or `"generic"`, the caller-supplied `url` is used.
/// For known providers, the well-known URL is returned even if `url` is `None`.
#[must_use]
pub fn resolve_base_url(provider: Option<&str>, url: Option<&str>) -> Option<String> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn fastmail_custom_url_overrides() {
    ...
}

    #[test]
    fn icloud_defaults_to_well_known() {
    ...
}

    #[test]
    fn generic_requires_explicit_url() {
    ...
}

    #[test]
    fn none_provider_requires_explicit_url() {
    ...
}
}
