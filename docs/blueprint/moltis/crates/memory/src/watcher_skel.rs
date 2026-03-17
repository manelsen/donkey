/// Real-time file watching for memory sync using notify-debouncer-full.
use std::path::PathBuf;

use {
    anyhow::Result,
    notify_debouncer_full::{
        DebounceEventResult, Debouncer, RecommendedCache, new_debouncer, notify::RecursiveMode,
    },
    tokio::sync::mpsc,
    tracing::{debug, info, warn},
};

/// Events emitted by the file watcher.
#[derive(Debug, Clone)]
pub enum WatchEvent {
    ...
}

/// Watches directories for markdown file changes with debouncing.
pub struct MemoryFileWatcher {
    ...
}

impl MemoryFileWatcher {
    /// Start watching the given directories. Returns the watcher and a receiver for events.
    pub fn start(dirs: Vec<PathBuf>) -> Result<(Self, mpsc::UnboundedReceiver<WatchEvent>)> {
}
