use std::{collections::HashMap, future::Future, pin::Pin, sync::Arc};

use tracing::{debug, warn};

use moltis_protocol::{ErrorShape, ResponseFrame, error_codes};

use crate::state::GatewayState;

mod channel_mux;
mod gateway;
mod node;
mod pairing;
mod services;
mod subscribe;
mod voice;

// ── Types ────────────────────────────────────────────────────────────────────

/// Context passed to every method handler.
pub struct MethodContext {
    ...
}

/// The result a method handler produces.
pub type MethodResult = Result<serde_json::Value, ErrorShape>;

/// A boxed async method handler.
pub type HandlerFn =
    Box<dyn Fn(MethodContext) -> Pin<Box<dyn Future<Output = MethodResult> + Send>> + Send + Sync>;

// ── Scope authorization ──────────────────────────────────────────────────────

const NODE_METHODS: &[&str] = &["node.invoke.result", "node.event", "skills.bins"];

const READ_METHODS: &[&str] = &[
    "health",
    "logs.tail",
    "logs.list",
    "logs.status",
    "channels.status",
    "channels.list",
    "channels.senders.list",
    "status",
    "usage.status",
    "usage.cost",
    "tts.status",
    "tts.providers",
    "stt.status",
    "stt.providers",
    "models.list",
    "models.list_all",
    #[cfg(feature = "agent")]
    "agents.list",
    #[cfg(feature = "agent")]
    "agents.get",
    #[cfg(feature = "agent")]
    "agents.identity.get",
    #[cfg(feature = "agent")]
    "agents.files.list",
    #[cfg(feature = "agent")]
    "agents.files.get",
    "agent.identity.get",
    "skills.list",
    "skills.status",
    "skills.security.status",
    "skills.security.scan",
    "skills.repos.list",
    "voicewake.get",
    "sessions.list",
    "sessions.preview",
    "sessions.search",
    "sessions.branches",
    "sessions.run_detail",
    "sessions.share.list",
    "projects.list",
    "projects.get",
    "projects.context",
    "projects.complete_path",
    "cron.list",
    "cron.status",
    "cron.runs",
    "heartbeat.status",
    "heartbeat.runs",
    "system-presence",
    "last-heartbeat",
    "node.list",
    "node.describe",
    "chat.history",
    "chat.context",
    "chat.raw_prompt",
    "providers.available",
    "providers.oauth.status",
    "providers.local.system_info",
    "providers.local.models",
    "providers.local.status",
    "providers.local.search_hf",
    "mcp.list",
    "mcp.status",
    "mcp.tools",
    "tts.generate_phrase",
    "voice.config.get",
    "voice.config.voxtral_requirements",
    "voice.providers.all",
    "voice.elevenlabs.catalog",
    #[cfg(feature = "graphql")]
    "graphql.config.get",
    "memory.status",
    "memory.config.get",
    "memory.qmd.status",
    "hooks.list",
    "network.audit.list",
    "network.audit.tail",
    "network.audit.stats",
    "openclaw.detect",
    "openclaw.scan",
    "system.describe",
];

const WRITE_METHODS: &[&str] = &[
    "send",
    "agent",
    "agent.wait",
    "agent.identity.update",
    "agent.identity.update_soul",
    #[cfg(feature = "agent")]
    "agents.create",
    #[cfg(feature = "agent")]
    "agents.update",
    #[cfg(feature = "agent")]
    "agents.delete",
    #[cfg(feature = "agent")]
    "agents.set_default",
    #[cfg(feature = "agent")]
    "agents.set_session",
    #[cfg(feature = "agent")]
    "agents.identity.update",
    #[cfg(feature = "agent")]
    "agents.identity.update_soul",
    #[cfg(feature = "agent")]
    "agents.files.set",
    "wake",
    "talk.mode",
    "tts.enable",
    "tts.disable",
    "tts.convert",
    "tts.setProvider",
    "stt.transcribe",
    "stt.setProvider",
    "voicewake.set",
    "node.invoke",
    "nodes.set_session",
    "chat.send",
    "chat.abort",
    "chat.cancel_queued",
    "chat.clear",
    "chat.compact",
    "browser.request",
    "logs.ack",
    "models.detect_supported",
    "models.test",
    "providers.save_key",
    "providers.save_model",
    "providers.save_models",
    "providers.validate_key",
    "providers.remove_key",
    "providers.add_custom",
    "providers.oauth.start",
    "providers.oauth.complete",
    "providers.local.configure",
    "providers.local.configure_custom",
    "channels.add",
    "channels.remove",
    "channels.update",
    "channels.senders.approve",
    "channels.senders.deny",
    "sessions.switch",
    "sessions.fork",
    "sessions.voice.generate",
    "sessions.clear_all",
    "sessions.share.create",
    "sessions.share.revoke",
    "projects.upsert",
    "projects.delete",
    "projects.detect",
    "skills.install",
    "skills.remove",
    "skills.repos.remove",
    "skills.emergency_disable",
    "skills.skill.trust",
    "skills.skill.enable",
    "skills.skill.disable",
    "skills.install_dep",
    "mcp.add",
    "mcp.remove",
    "mcp.enable",
    "mcp.disable",
    "mcp.restart",
    "mcp.reauth",
    "mcp.update",
    "mcp.oauth.start",
    "mcp.oauth.complete",
    "cron.add",
    "cron.update",
    "cron.remove",
    "cron.run",
    "heartbeat.update",
    "heartbeat.run",
    "voice.config.save_key",
    "voice.config.save_settings",
    "voice.config.remove_key",
    "voice.provider.toggle",
    "voice.override.session.set",
    "voice.override.session.clear",
    "voice.override.channel.set",
    "voice.override.channel.clear",
    #[cfg(feature = "graphql")]
    "graphql.config.set",
    "memory.config.update",
    "hooks.enable",
    "hooks.disable",
    "hooks.save",
    "hooks.reload",
    "location.result",
    "openclaw.import",
    "subscribe",
    "unsubscribe",
    "channel.join",
    "channel.leave",
];

const APPROVAL_METHODS: &[&str] = &["exec.approval.request", "exec.approval.resolve"];

const PAIRING_METHODS: &[&str] = &[
    "node.pair.request",
    "node.pair.list",
    "node.pair.approve",
    "node.pair.reject",
    "node.pair.verify",
    "device.pair.list",
    "device.pair.approve",
    "device.pair.reject",
    "device.token.create",
    "device.token.rotate",
    "device.token.revoke",
    "node.rename",
];

fn is_in(method: &str, list: &[&str]) -> bool {
    ...
}

/// Check role + scopes for a method. Returns None if authorized, Some(error) if not.
pub fn authorize_method(method: &str, role: &str, scopes: &[String]) -> Option<ErrorShape> {
    ...
}

// ── Method registry ──────────────────────────────────────────────────────────

pub struct MethodRegistry {
    ...
}

impl Default for MethodRegistry {
    fn default() -> Self {
}

impl MethodRegistry {
    pub fn new() -> Self {

    pub fn register(&mut self, method: impl Into<String>, handler: HandlerFn) {
    ...
}

    pub async fn dispatch(&self, ctx: MethodContext) -> ResponseFrame {
    ...
}

    pub fn method_names(&self) -> Vec<String> {
    ...
}

    fn register_defaults(&mut self) {
    ...
}
}

/// Load the disabled hooks set from `data_dir/disabled_hooks.json`.
pub(crate) fn load_disabled_hooks() -> std::collections::HashSet<String> {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used, clippy::expect_used)]
mod tests {

    fn assert_error_code(result: Option<ErrorShape>, expected_code: &str) {
    ...
}

    #[test]
    fn senders_list_requires_read() {
    ...
}

    #[test]
    fn senders_approve_requires_write() {
    ...
}

    #[test]
    fn senders_deny_requires_write() {
    ...
}

    #[test]
    fn admin_scope_allows_all_sender_methods() {
    ...
}

    #[test]
    fn node_role_denied_sender_methods() {
    ...
}

    #[cfg(feature = "graphql")]
    #[test]
    fn graphql_config_get_requires_read() {
    ...
}

    #[cfg(feature = "graphql")]
    #[test]
    fn graphql_config_set_requires_write() {
    ...
}

    #[test]
    fn identity_get_requires_read() {
    ...
}

    #[test]
    fn identity_update_requires_write() {
    ...
}

    #[test]
    fn identity_update_soul_requires_write() {
    ...
}

    #[test]
    fn cron_read_methods_require_read() {
    ...
}

    #[test]
    fn cron_write_methods_require_write() {
    ...
}

    #[test]
    fn hooks_list_requires_read() {
    ...
}

    #[test]
    fn hooks_write_methods_require_write() {
    ...
}

    #[test]
    fn unknown_method_returns_unknown_code() {
    ...
}

    #[test]
    fn subscribe_method_authorized_with_write() {
    ...
}

    #[test]
    fn channel_join_authorized_with_write() {
    ...
}

    #[test]
    fn system_describe_authorized_with_read() {
    ...
}

    #[test]
    fn model_probe_params_include_provider_when_present() {
    ...
}

    #[test]
    fn model_probe_params_omit_provider_when_missing() {
    ...
}

    #[test]
    fn model_probe_params_omit_provider_when_blank() {
    ...
}
}
