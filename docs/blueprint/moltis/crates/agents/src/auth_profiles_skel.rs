/// OAuth + API key credential management with token refresh, stored per-agent.
use secrecy::Secret;

pub struct AuthProfile {
    ...
}

pub enum Credentials {
    ...
}

/// Refresh credentials if expired.
pub async fn refresh_if_needed(_profile: &mut AuthProfile) -> anyhow::Result<()> {
    ...
}
