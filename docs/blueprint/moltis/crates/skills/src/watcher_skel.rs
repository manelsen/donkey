//! Filesystem watcher for skill directories.
//!
//! Watches skill search paths for SKILL.md create/modify/delete events and sends
//! notifications through a channel so the gateway can broadcast `skills.changed`.

use std::path::PathBuf;

use {
    anyhow::Result,
    notify_debouncer_full::{
        DebounceEventResult, Debouncer, RecommendedCache, new_debouncer, notify::RecursiveMode,
    },
    tokio::sync::mpsc,
    tracing::{debug, info, warn},
};

/// Events emitted by the skill watcher.
#[derive(Debug, Clone)]
pub enum SkillWatchEvent {
    ...
}

/// Watches skill directories for SKILL.md changes with debouncing.
pub struct SkillWatcher {
    ...
}

impl SkillWatcher {
    /// Start watching the given directories. Returns the watcher and a receiver for events.
    ///
    /// The watcher must be kept alive (not dropped) for events to continue.
    pub fn start(dirs: Vec<PathBuf>) -> Result<(Self, mpsc::UnboundedReceiver<SkillWatchEvent>)> {
}
