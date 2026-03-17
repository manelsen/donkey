use std::{collections::HashMap, time::Instant};

#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

pub type Result<T> = std::result::Result<T, Error>;

/// A provider discovered on a remote node.
#[derive(Debug, Clone)]
pub struct NodeProviderEntry {
    ...
}

/// A connected device node (macOS, iOS, Android).
#[derive(Debug, Clone)]
pub struct NodeSession {
    ...
}

/// Registry of connected device nodes and their capabilities.
pub struct NodeRegistry {
    ...
}

impl Default for NodeRegistry {
    fn default() -> Self {
}

impl NodeRegistry {
    pub fn new() -> Self {

    pub fn register(&mut self, session: NodeSession) {
    ...
}

    pub fn unregister_by_conn(&mut self, conn_id: &str) -> Option<NodeSession> {
    ...
}

    pub fn get(&self, node_id: &str) -> Option<&NodeSession> {
    ...
}

    pub fn get_mut(&mut self, node_id: &str) -> Option<&mut NodeSession> {
    ...
}

    pub fn list(&self) -> Vec<&NodeSession> {
    ...
}

    pub fn has_mobile_node(&self) -> bool {
    ...
}

    pub fn rename(&mut self, node_id: &str, display_name: &str) -> Result<()> {
    ...
}

    /// Update telemetry data for a node.
    pub fn update_telemetry(
        &mut self,
        node_id: &str,
        mem_total: Option<u64>,
        mem_available: Option<u64>,
        cpu_count: Option<u32>,
        cpu_usage: Option<f32>,
        uptime_secs: Option<u64>,
        services: Vec<String>,
        disk_total: Option<u64>,
        disk_available: Option<u64>,
        runtimes: Vec<String>,
    ) -> Result<()> {
    ...
}

    /// Remove all nodes (used when disconnecting all clients).
    pub fn clear(&mut self) {
    ...
}

    pub fn count(&self) -> usize {
    ...
}
}
