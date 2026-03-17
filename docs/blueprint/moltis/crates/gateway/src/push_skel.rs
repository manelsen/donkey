//! Push notification support for PWA clients.
//!
//! Handles VAPID key generation/storage, subscription management, and sending
//! push notifications when the LLM responds while the user is not actively
//! viewing the chat.

use {
    anyhow::{Context, Result},
    base64::Engine,
    chrono::{DateTime, Utc},
    p256::{
        PublicKey, ecdsa::SigningKey, elliptic_curve::rand_core::OsRng, pkcs8::EncodePrivateKey,
    },
    serde::{Deserialize, Serialize},
    std::{path::PathBuf, sync::Arc},
    tokio::sync::RwLock,
    tracing::{debug, error, info, warn},
    web_push::{
        ContentEncoding, SubscriptionInfo, VapidSignatureBuilder, WebPushClient,
        WebPushMessageBuilder,
    },
};

/// VAPID keys for push notifications.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VapidKeys {
    ...
}

/// A push subscription from a browser.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PushSubscription {
    ...
}

/// Payload for a push notification.
#[derive(Debug, Clone, Serialize)]
pub struct PushPayload {
    ...
}

/// Stored push data (VAPID keys + subscriptions).
#[derive(Debug, Default, Serialize, Deserialize)]
struct PushStore {
    ...
}

/// Push notification service.
pub struct PushService {
    ...
}

impl PushService {
    /// Create a new push service, loading or generating VAPID keys.
    pub async fn new(data_dir: &std::path::Path) -> Result<Arc<Self>> {

    /// Generate new VAPID keys and save them.
    async fn generate_vapid_keys(&self) -> Result<()> {
    ...
}

    /// Get the VAPID public key for clients.
    pub async fn vapid_public_key(&self) -> Option<String> {
    ...
}

    /// Add a new push subscription.
    pub async fn add_subscription(&self, sub: PushSubscription) -> Result<()> {
    ...
}

    /// Remove a subscription by endpoint.
    pub async fn remove_subscription(&self, endpoint: &str) -> Result<()> {
    ...
}

    /// Get the number of active subscriptions.
    pub async fn subscription_count(&self) -> usize {
    ...
}

    /// Get all subscriptions (for admin display).
    pub async fn list_subscriptions(&self) -> Vec<PushSubscription> {
    ...
}

    /// Send a push notification to all subscriptions.
    pub async fn send_to_all(&self, payload: &PushPayload) -> Result<usize> {
    ...
}

    /// Send a push notification to a single subscription.
    async fn send_to_subscription(
        &self,
        vapid: &VapidKeys,
        sub: &PushSubscription,
        payload: &[u8],
    ) -> Result<()> {
    ...
}

    /// Save the store to disk.
    async fn save_store(&self) -> Result<()> {
    ...
}
}
