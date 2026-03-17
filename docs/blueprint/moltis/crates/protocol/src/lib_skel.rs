//! Gateway WebSocket/RPC protocol definitions.
//!
//! Protocol version 4 (backward-compatible with v3). All communication uses JSON frames over WebSocket.
//!
//! Frame types:
//! - `RequestFrame`  — client → gateway RPC call (also server → client in v4)
//! - `ResponseFrame` — gateway → client RPC result (also client → server in v4)
//! - `EventFrame`    — gateway → client server-push

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

// ── Constants ────────────────────────────────────────────────────────────────

pub const PROTOCOL_VERSION: u32 = 4;
pub const MAX_PAYLOAD_BYTES: usize = 524_288; // 512 KB
pub const MAX_BUFFERED_BYTES: usize = 1_572_864; // 1.5 MB
pub const TICK_INTERVAL_MS: u64 = 30_000; // 30s
pub const HANDSHAKE_TIMEOUT_MS: u64 = 10_000; // 10s
pub const DEDUPE_TTL_MS: u64 = 300_000; // 5 min
pub const DEDUPE_MAX_ENTRIES: usize = 1_000;

// ── Subscriptions ────────────────────────────────────────────────────────────

pub mod subscriptions {
    /// Wildcard subscription: receive all events.
    pub const WILDCARD: &str = "*";
}

// ── Error codes ──────────────────────────────────────────────────────────────

pub mod error_codes {
    // v3 backward-compat codes
    pub const NOT_LINKED: &str = "NOT_LINKED";
    pub const NOT_PAIRED: &str = "NOT_PAIRED";
    pub const AGENT_TIMEOUT: &str = "AGENT_TIMEOUT";
    pub const INVALID_REQUEST: &str = "INVALID_REQUEST";
    pub const UNAVAILABLE: &str = "UNAVAILABLE";

    // v4 standardized codes
    pub const UNKNOWN_METHOD: &str = "UNKNOWN_METHOD";
    pub const UNAUTHORIZED: &str = "UNAUTHORIZED";
    pub const FORBIDDEN: &str = "FORBIDDEN";
    pub const NOT_FOUND: &str = "NOT_FOUND";
    pub const CONFLICT: &str = "CONFLICT";
    pub const RATE_LIMITED: &str = "RATE_LIMITED";
    pub const TIMEOUT: &str = "TIMEOUT";
    pub const INTERNAL: &str = "INTERNAL";
    pub const PROTOCOL_ERROR: &str = "PROTOCOL_ERROR";
    pub const PAYLOAD_TOO_LARGE: &str = "PAYLOAD_TOO_LARGE";
}

// ── Error shape ──────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ErrorShape {
    ...
}

impl ErrorShape {
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
}

// ── Frames ───────────────────────────────────────────────────────────────────

/// Client → gateway RPC request. Also used server → client in v4 bidirectional RPC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestFrame {
    ...
}

/// Gateway → client RPC response. Also client → server in v4 bidirectional RPC.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResponseFrame {
    ...
}

impl ResponseFrame {
    pub fn ok(id: impl Into<String>, payload: serde_json::Value) -> Self {

    pub fn err(id: impl Into<String>, error: ErrorShape) -> Self {
    ...
}
}

/// Gateway → client server-push event.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventFrame {
    ...
}

impl EventFrame {
    pub fn new(event: impl Into<String>, payload: serde_json::Value, seq: u64) -> Self {

    /// Create an event frame with stream metadata.
    pub fn streamed(
        event: impl Into<String>,
        payload: serde_json::Value,
        seq: u64,
        stream_id: String,
        done: bool,
    ) -> Self {
    ...
}
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StateVersion {
    ...
}

/// Discriminated union of all frame types.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum GatewayFrame {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RequestFrameInner {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResponseFrameInner {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventFrameInner {
    ...
}

// ── Extensions ───────────────────────────────────────────────────────────────

/// Namespaced extension data for protocol-agnostic transport.
pub type Extensions = HashMap<String, serde_json::Value>;

// ── Connect handshake ────────────────────────────────────────────────────────

/// Protocol version range for v4 negotiation.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ProtocolRange {
    ...
}

/// v4 connect parameters: flat core + namespaced extensions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectParamsV4 {
    ...
}

impl ConnectParamsV4 {
    /// Convert to v3-compatible `ConnectParams` for internal processing.
    pub fn into_connect_params(self) -> ConnectParams {
}

/// Parameters sent by the client in the initial `connect` request (v3 format).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectParams {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ClientInfo {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DeviceInfo {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConnectAuth {
    ...
}

/// Sent by the gateway after successful handshake.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelloOk {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerInfo {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Features {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelloAuth {
    ...
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Policy {
    ...
}

impl Default for Policy {
    fn default() -> Self {
}

// ── Known events ─────────────────────────────────────────────────────────────

pub const KNOWN_EVENTS: &[&str] = &[
    "tick",
    "shutdown",
    "agent",
    "chat",
    "presence",
    "health",
    "exec.approval.requested",
    "exec.approval.resolved",
    "device.pair.requested",
    "device.pair.resolved",
    "node.pair.requested",
    "node.pair.resolved",
    "node.invoke.request",
];

// ── Roles and scopes ─────────────────────────────────────────────────────────

pub mod roles {
    pub const OPERATOR: &str = "operator";
    pub const NODE: &str = "node";
}

pub mod scopes {
    pub const ADMIN: &str = "operator.admin";
    pub const READ: &str = "operator.read";
    pub const WRITE: &str = "operator.write";
    pub const APPROVALS: &str = "operator.approvals";
    pub const PAIRING: &str = "operator.pairing";
}

// ── Schema discovery (v4) ────────────────────────────────────────────────────

/// Describes a single RPC method for `system.describe`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MethodDescriptor {
    ...
}

/// Describes a server-push event for `system.describe`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct EventDescriptor {
    ...
}

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn v4_connect_params_parses_and_converts() {
    ...
}

    #[test]
    fn v4_connect_params_empty_extensions() {
    ...
}

    // ── EventFrame with stream/done/channel ────────────────────────────

    #[test]
    fn event_frame_new_omits_stream_fields() {
    ...
}

    #[test]
    fn event_frame_streamed_includes_metadata() {
    ...
}

    #[test]
    fn event_frame_stream_done_marker() {
    ...
}

    #[test]
    fn event_frame_round_trip_with_channel() {
    ...
}

    // ── RequestFrame with channel ──────────────────────────────────────

    #[test]
    fn request_frame_channel_serialization() {
    ...
}

    #[test]
    fn request_frame_omits_null_channel() {
    ...
}

    // ── HelloOk extensions ─────────────────────────────────────────────

    #[test]
    fn hello_ok_empty_extensions_not_serialized() {
    ...
}

    #[test]
    fn hello_ok_with_extensions_serialized() {
    ...
}

    // ── Error codes ────────────────────────────────────────────────────

    #[test]
    fn new_error_codes_exist() {
    ...
}

    // ── GatewayFrame round-trip with new fields ────────────────────────

    #[test]
    fn gateway_frame_response_round_trip() {
    ...
}

    #[test]
    fn gateway_frame_event_with_stream() {
    ...
}

    // ── Schema descriptors ─────────────────────────────────────────────

    #[test]
    fn method_descriptor_round_trip() {
    ...
}
}
