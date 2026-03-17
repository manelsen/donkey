use {
    anyhow::Result,
    async_trait::async_trait,
    moltis_agents::tool_registry::AgentTool,
    serde_json::{Value, json},
    std::sync::Arc,
};

use crate::services::ChannelService;

/// Agent tool that sends proactive outbound messages to configured channels.
///
/// Validation and alias resolution are handled by the underlying
/// [`ChannelService::send`] implementation; this tool only provides the
/// LLM-facing schema and forwards the parameters.
pub struct SendMessageTool {
    ...
}

impl SendMessageTool {
    pub fn new(channel_service: Arc<dyn ChannelService>) -> Self {
}

#[async_trait]
impl AgentTool for SendMessageTool {
    fn name(&self) -> &str {

    fn description(&self) -> &str {
    ...
}

    fn parameters_schema(&self) -> Value {
    ...
}

    async fn execute(&self, params: Value) -> Result<Value> {
    ...
}
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    struct RecordingChannelService {
    ...
}

    impl RecordingChannelService {
        fn new() -> Self {
    }

    #[async_trait]
    impl ChannelService for RecordingChannelService {
        async fn status(&self) -> ServiceResult {

        async fn logout(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn send(&self, params: Value) -> ServiceResult {
    ...
}

        async fn add(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn remove(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn update(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn senders_list(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn sender_approve(&self, _params: Value) -> ServiceResult {
    ...
}

        async fn sender_deny(&self, _params: Value) -> ServiceResult {
    ...
}
    }

    #[tokio::test]
    async fn send_message_tool_forwards_params_to_channel_service() {
    ...
}

    #[tokio::test]
    async fn send_message_tool_propagates_service_errors() {
    ...
}
}
