//! GraphQL subscription resolvers.
//!
//! Subscriptions bridge from the gateway's broadcast channel. Each subscription
//! filters events by name and deserializes the payload into typed events.

use std::sync::Arc;

use {
    async_graphql::{Context, Result, Subscription},
    tokio_stream::Stream,
};

use crate::{
    context::GqlContext,
    types::{GenericEvent, TickEvent},
};

/// Root subscription type.
#[derive(Default)]
pub struct SubscriptionRoot;

#[Subscription]
impl SubscriptionRoot {
    /// Chat events (streaming tokens, completion, abort).
    async fn chat_event(
        &self,
        ctx: &Context<'_>,
        session_key: Option<String>,
    ) -> Result<impl Stream<Item = GenericEvent>> {

    /// Session change events (patch, switch, delete).
    async fn session_changed(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Cron job notifications (created, updated, removed, run complete).
    async fn cron_notification(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Channel events.
    async fn channel_event(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Node connect/disconnect events.
    async fn node_event(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// System tick events (periodic heartbeat with stats).
    async fn tick(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = TickEvent>> {
    ...
}

    /// Log entry events.
    async fn log_entry(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// MCP server status change events.
    async fn mcp_status_changed(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Execution approval events.
    async fn approval_event(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Config change events.
    async fn config_changed(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// System presence change events.
    async fn presence_changed(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Metrics update events.
    async fn metrics_update(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Update availability events.
    async fn update_available(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Voice config changed events.
    async fn voice_config_changed(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// Skills install progress events.
    async fn skills_install_progress(
        &self,
        ctx: &Context<'_>,
    ) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}

    /// All events (unfiltered, for debugging).
    async fn all_events(&self, ctx: &Context<'_>) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}
}

/// Helper to create a filtered event stream for a specific event name.
async fn event_stream(
    ctx: &Context<'_>,
    event_name: &'static str,
) -> Result<impl Stream<Item = GenericEvent>> {
    ...
}
