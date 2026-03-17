//! Session event bus for cross-UI synchronization.
//!
//! A `tokio::sync::broadcast` channel carries lightweight [`SessionEvent`]
//! values so both the macOS bridge FFI and gateway WebSocket layer can
//! observe session lifecycle updates.

use tokio::sync::broadcast;

/// A change to a session that other UIs should know about.
#[derive(Clone, Debug)]
pub enum SessionEvent {
    ...
}

/// Thin wrapper around a `broadcast::Sender<SessionEvent>`.
///
/// Cloning the bus is cheap (Arc internally) and gives each holder
/// the ability to both publish and subscribe.
#[derive(Clone, Debug)]
pub struct SessionEventBus {
    ...
}

impl Default for SessionEventBus {
    fn default() -> Self {
}

impl SessionEventBus {
    /// Create a new bus with a bounded capacity of 64 events.
    pub fn new() -> Self {

    /// Publish an event. Returns the number of active receivers.
    /// If there are no subscribers the event is silently dropped.
    pub fn publish(&self, event: SessionEvent) -> usize {
    ...
}

    /// Subscribe to the event stream.
    pub fn subscribe(&self) -> broadcast::Receiver<SessionEvent> {
    ...
}
}

#[cfg(test)]
mod tests {

    #[tokio::test]
    async fn publish_without_subscribers_does_not_panic() {
    ...
}
}
