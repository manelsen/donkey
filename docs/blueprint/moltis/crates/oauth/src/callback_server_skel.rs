use std::{collections::HashMap, sync::Arc};

use {
    axum::{Router, extract::Query, response::Html, routing::get},
    tokio::sync::oneshot,
};

use crate::{Error, Result};

/// Starts a local HTTP server to receive the OAuth callback, then shuts down.
pub struct CallbackServer;

impl CallbackServer {
    /// Listen on ` {
    /// Validates state matches `expected_state`, returns the authorization code.
    /// Times out after 60 seconds.
    pub async fn wait_for_code(
        port: u16,
        expected_state: String,
        bind_addr: &str,
    ) -> Result<String> {
    ...
}
}
