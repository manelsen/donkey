//! Kimi-specific helpers for OAuth device flow and API requests.

use reqwest::header::{HeaderMap, HeaderValue};

use crate::config_dir::moltis_config_dir;

/// Get or generate a persistent device ID for Kimi API headers.
/// Stored at `~/.config/moltis/kimi_device_id`.
pub fn get_or_create_device_id() -> String {
    ...
}

fn get_or_create_device_id_at(path: &std::path::Path) -> String {
    ...
}

/// Build the `X-Msh-*` headers required by Kimi's OAuth and API endpoints.
pub fn kimi_headers() -> HeaderMap {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn device_id_is_stable() -> std::io::Result<()> {
    ...
}
}
