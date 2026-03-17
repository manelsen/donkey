use {
    anyhow::Result,
    async_trait::async_trait,
    base64::Engine,
    moltis_agents::tool_registry::AgentTool,
    serde::{Deserialize, Serialize},
    serde_json::{Value, json},
    std::{path::PathBuf, sync::Arc},
    uuid::Uuid,
};

use crate::{services::TtsService, voice::SttService};

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SpeakToolParams {
    ...
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct TtsConvertParams {
    ...
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct TtsConvertResult {
    ...
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SpeakToolResult {
    ...
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct TranscribeToolParams {
    ...
}

#[derive(Debug, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct TranscribeToolResult {
    ...
}

pub struct SpeakTool {
    ...
}

impl SpeakTool {
    pub fn new(tts: Arc<dyn TtsService>) -> Self {
}

#[async_trait]
impl AgentTool for SpeakTool {
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

pub struct TranscribeTool {
    ...
}

impl TranscribeTool {
    pub fn new(stt: Arc<dyn SttService>) -> Self {
}

#[async_trait]
impl AgentTool for TranscribeTool {
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

fn write_tool_audio_file(file_name: &str, bytes: &[u8]) -> Result<String> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {
