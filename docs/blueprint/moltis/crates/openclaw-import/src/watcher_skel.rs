//! Filesystem watcher for OpenClaw session directories.
//!
//! Watches the OpenClaw sessions directory for `.jsonl` create/modify events and
//! sends coalesced notifications so the gateway can run incremental session import.

use std::path::PathBuf;

use {
    notify_debouncer_full::{
        DebounceEventResult, Debouncer, RecommendedCache, new_debouncer, notify::RecursiveMode,
    },
    tokio::sync::mpsc,
    tracing::{debug, info, warn},
};

use crate::error::Result;

/// Events emitted by the import watcher.
#[derive(Debug, Clone)]
pub enum ImportWatchEvent {
    ...
}

/// Watches an OpenClaw sessions directory for JSONL changes with debouncing.
pub struct ImportWatcher {
    ...
}

impl ImportWatcher {
    /// Start watching the given sessions directory. Returns the watcher and a
    /// receiver for coalesced events.
    ///
    /// The watcher must be kept alive (not dropped) for events to continue.
    /// Uses a 5-second debounce window because OpenClaw appends frequently
    /// to session JSONL files during active conversations.
    pub fn start(
        sessions_dir: PathBuf,
    ) -> Result<(Self, mpsc::UnboundedReceiver<ImportWatchEvent>)> {
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    #[tokio::test]
    async fn watcher_ignores_non_jsonl_files() {
    ...
}
}
