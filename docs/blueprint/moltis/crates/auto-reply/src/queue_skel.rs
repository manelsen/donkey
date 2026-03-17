/// Per-session followup queue for inbound messages.
///
/// Modes: per-message, batch, debounce.
/// Drop policies: oldest, newest, none.

#[derive(Debug, Clone)]
pub enum QueueMode {
    ...
}

#[derive(Debug, Clone)]
pub enum DropPolicy {
    ...
}
