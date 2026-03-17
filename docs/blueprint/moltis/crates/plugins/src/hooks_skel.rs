//! Hook system — re-exports core types from `moltis-common` and adds config.

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

// Re-export all core hook types so downstream code can use `moltis_plugins::hooks::*`.
pub use moltis_common::hooks::{
    HookAction, HookEvent, HookHandler, HookPayload, HookRegistry, HookStats,
};

// ── Hook configuration ──────────────────────────────────────────────────────

/// Configuration for a single shell hook, loaded from TOML/config.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ShellHookConfig {
    ...
}

fn default_timeout() -> u64 {
    ...
}

/// Top-level hooks configuration section.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct HooksConfig {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    use super::*;

    struct PassthroughHandler {
    ...
}

    #[async_trait]
    impl HookHandler for PassthroughHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    struct BlockingHandler {
    ...
}

    #[async_trait]
    impl HookHandler for BlockingHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    struct ModifyHandler {
    ...
}

    #[async_trait]
    impl HookHandler for ModifyHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    struct FailingHandler {
    ...
}

    #[async_trait]
    impl HookHandler for FailingHandler {
        fn name(&self) -> &str {

        fn events(&self) -> &[HookEvent] {
    ...
}

        async fn handle(&self, _event: HookEvent, _payload: &HookPayload) -> Result<HookAction> {
    ...
}
    }

    fn test_payload() -> HookPayload {
    ...
}

    #[tokio::test]
    async fn dispatch_with_no_handlers_returns_continue() {
    ...
}

    #[tokio::test]
    async fn dispatch_passthrough_returns_continue() {
    ...
}

    #[tokio::test]
    async fn dispatch_block_short_circuits() {
    ...
}

    #[tokio::test]
    async fn dispatch_modify_returns_last_modification() {
    ...
}

    #[tokio::test]
    async fn dispatch_error_is_non_fatal() {
    ...
}

    #[tokio::test]
    async fn has_handlers_returns_correct_values() {
    ...
}

    #[tokio::test]
    async fn unrelated_events_dont_trigger() {
    ...
}

    #[test]
    fn payload_event_matches() {
    ...
}

    #[test]
    fn hook_payload_serializes_roundtrip() {
    ...
}

    #[test]
    fn hook_config_deserializes() {
    ...
}
}
