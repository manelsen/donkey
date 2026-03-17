//! McpRegistry: persisted configuration of MCP servers (add/remove/enable/disable).

use std::{
    collections::HashMap,
    path::{Path, PathBuf},
};

use {
    secrecy::{ExposeSecret, Secret},
    serde::{Deserialize, Serialize},
    tracing::{debug, info},
};

use crate::error::{Context, Result};

/// Transport type for MCP server connections.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "lowercase")]
pub enum TransportType {
    ...
}

/// Manual OAuth override for MCP servers that don't support standard discovery.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpOAuthConfig {
    ...
}

/// Configuration for a single MCP server.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct McpServerConfig {
    ...
}

fn default_true() -> bool {
    ...
}

impl Default for McpServerConfig {
    fn default() -> Self {
}

/// Persisted registry of MCP server configurations.
#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct McpRegistry {
    ...
}

impl McpRegistry {
    /// Create a new empty registry.
    pub fn new() -> Self {

    /// Load from a JSON file, or return empty if the file doesn't exist.
    pub fn load(path: &Path) -> Result<Self> {
    ...
}

    /// Save to the registry file.
    pub fn save(&self) -> Result<()> {
    ...
}

    /// Add or update a server configuration.
    pub fn add(&mut self, name: String, config: McpServerConfig) -> Result<()> {
    ...
}

    /// Remove a server configuration.
    pub fn remove(&mut self, name: &str) -> Result<bool> {
    ...
}

    /// Enable a server.
    pub fn enable(&mut self, name: &str) -> Result<bool> {
    ...
}

    /// Disable a server.
    pub fn disable(&mut self, name: &str) -> Result<bool> {
    ...
}

    /// List all server names.
    pub fn list(&self) -> Vec<&str> {
    ...
}

    /// Get a server config by name.
    pub fn get(&self, name: &str) -> Option<&McpServerConfig> {
    ...
}

    /// Get all enabled server configs.
    pub fn enabled_servers(&self) -> Vec<(&str, &McpServerConfig)> {
    ...
}
}

fn serialize_option_secret_string<S: serde::Serializer>(
    secret: &Option<Secret<String>>,
    serializer: S,
) -> std::result::Result<S::Ok, S::Error> {
    match secret {
        Some(value) => serializer.serialize_some(value.expose_secret()),
        None => serializer.serialize_none(),
    }
}

fn deserialize_option_secret_string<'de, D>(
    deserializer: D,
) -> std::result::Result<Option<Secret<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let opt: Option<String> = Option::deserialize(deserializer)?;
    Ok(opt.map(Secret::new))
}

fn serialize_secret_string_map<S: serde::Serializer>(
    values: &HashMap<String, Secret<String>>,
    serializer: S,
) -> std::result::Result<S::Ok, S::Error> {
    let plain: HashMap<&str, &str> = values
        .iter()
        .map(|(key, value)| (key.as_str(), value.expose_secret().as_str()))
        .collect();
    plain.serialize(serializer)
}

fn deserialize_secret_string_map<'de, D>(
    deserializer: D,
) -> std::result::Result<HashMap<String, Secret<String>>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let plain: HashMap<String, String> = HashMap::deserialize(deserializer)?;
    Ok(plain
        .into_iter()
        .map(|(key, value)| (key, Secret::new(value)))
        .collect())
}

#[cfg(test)]
mod tests {
