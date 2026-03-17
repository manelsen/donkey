use {
    crate::tool_registry::ToolRegistry,
    moltis_config::{AgentIdentity, DEFAULT_SOUL, UserProfile},
    moltis_skills::types::SkillMetadata,
};

// ── Model family detection ──────────────────────────────────────────────────

/// Broad model family classification, used to tune text-based tool prompts.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ModelFamily {
    ...
}

impl ModelFamily {
    /// Detect the model family from a model identifier string.
    #[must_use]
    pub fn from_model_id(id: &str) -> Self {
}

/// Runtime context for the host process running the current agent turn.
#[derive(Debug, Clone, Default)]
pub struct PromptHostRuntimeContext {
    ...
}

/// Runtime context for sandbox execution routing used by the `exec` tool.
#[derive(Debug, Clone, Default)]
pub struct PromptSandboxRuntimeContext {
    ...
}

/// Info about a single connected remote node, injected into the system prompt.
#[derive(Debug, Clone)]
pub struct PromptNodeInfo {
    ...
}

/// Runtime context about connected remote nodes.
#[derive(Debug, Clone, Default)]
pub struct PromptNodesRuntimeContext {
    ...
}

/// Combined runtime context injected into the system prompt.
#[derive(Debug, Clone, Default)]
pub struct PromptRuntimeContext {
    ...
}

/// Suffix appended to the system prompt when the user's reply medium is voice.
///
/// Instructs the LLM to produce speech-friendly output: no raw URLs, no markdown
/// formatting, concise conversational prose. This is Layer 1 of the voice-friendly
/// response pipeline; Layer 2 (`sanitize_text_for_tts`) catches anything the model
/// misses.
pub const VOICE_REPLY_SUFFIX: &str = "\n\n\
## Voice Reply Mode\n\n\
The user is speaking to you via voice messages. Their messages are transcribed from \
speech-to-text, so treat this as a spoken conversation. You will hear their words as \
text, and your response will be converted to spoken audio for them.\n\n\
Write for speech, not for reading:\n\
- Use natural, conversational sentences. No bullet lists, numbered lists, or headings.\n\
- NEVER include raw URLs. Instead describe the resource by name \
(e.g. \"the Rust documentation website\" instead of \"https://doc.rust-lang.org\").\n\
- No markdown formatting: no bold, italic, headers, code fences, or inline backticks.\n\
- Spell out abbreviations that a text-to-speech engine might mispronounce \
(e.g. \"API\" → \"A-P-I\", \"CLI\" → \"C-L-I\").\n\
- Keep responses concise — two to three short paragraphs at most.\n\
- Use complete sentences and natural transitions between ideas.\n";

/// Build the system prompt for an agent run, including available tools.
///
/// When `native_tools` is true, tool schemas are sent via the API's native
/// tool-calling mechanism (e.g. OpenAI function calling, Anthropic tool_use).
/// When false, tools are described in the prompt itself and the LLM is
/// instructed to emit tool calls as JSON blocks that the runner can parse.
pub fn build_system_prompt(
    tools: &ToolRegistry,
    native_tools: bool,
    project_context: Option<&str>,
) -> String {
    ...
}

/// Build the system prompt with explicit runtime context.
pub fn build_system_prompt_with_session_runtime(
    tools: &ToolRegistry,
    native_tools: bool,
    project_context: Option<&str>,
    skills: &[SkillMetadata],
    identity: Option<&AgentIdentity>,
    user: Option<&UserProfile>,
    soul_text: Option<&str>,
    agents_text: Option<&str>,
    tools_text: Option<&str>,
    runtime_context: Option<&PromptRuntimeContext>,
    memory_text: Option<&str>,
) -> String {
    ...
}

/// Build a minimal system prompt with explicit runtime context.
pub fn build_system_prompt_minimal_runtime(
    project_context: Option<&str>,
    identity: Option<&AgentIdentity>,
    user: Option<&UserProfile>,
    soul_text: Option<&str>,
    agents_text: Option<&str>,
    tools_text: Option<&str>,
    runtime_context: Option<&PromptRuntimeContext>,
    memory_text: Option<&str>,
) -> String {
    ...
}

/// Maximum number of characters from `MEMORY.md` injected into the system
/// prompt to keep the context window manageable.
const MEMORY_BOOTSTRAP_MAX_CHARS: usize = 8_000;
/// Maximum number of characters from project context files (`CLAUDE.md`,
/// project docs, etc.) injected into the prompt.
const PROJECT_CONTEXT_MAX_CHARS: usize = 8_000;
/// Maximum number of characters from each workspace file (`AGENTS.md`,
/// `TOOLS.md`) injected into the prompt.
const WORKSPACE_FILE_MAX_CHARS: usize = 6_000;
const EXEC_ROUTING_GUIDANCE_SANDBOX: &str = "Execution routing:\n\
- `exec` runs inside sandbox when `Sandbox(exec): enabled=true`.\n\
- When sandbox is disabled, `exec` runs on the host and may require approval.\n\
- In sandbox mode, `~` and relative paths resolve under `Sandbox(exec): home=...` (usually `/home/sandbox`).\n\
- Persistent workspace files live under `Host: data_dir=...`; when mounted, the same path appears as `Sandbox(exec): workspace_path=...`.\n";
const EXEC_ROUTING_SANDBOX_CLOSING: &str = "- Sandbox/host routing changes are expected runtime behavior. Do not frame them as surprising or anomalous.\n";
const EXEC_ROUTING_GUIDANCE_HOST_ONLY: &str = "Execution routing:\n\
- `exec` runs on the host and may require approval.\n";
const EXEC_ROUTING_SUDO_HINT: &str =
    "- `Host: sudo_non_interactive=true` means non-interactive sudo is available.\n";
/// Build model-family-aware tool call guidance for text-based tool mode.
fn tool_call_guidance(model_id: Option<&str>) -> String {
    ...
}

/// Format a tool schema in compact human-readable form for text-mode prompts.
///
/// Output: `### tool_name\ndescription\nParams: param1 (type, required), param2 (type)\n`
///
/// This is much shorter than dumping full JSON schema, saving ~60% context tokens.
fn format_compact_tool_schema(schema: &serde_json::Value) -> String {
    ...
}
const TOOL_GUIDELINES: &str = concat!(
    "## Guidelines\n\n",
    "- Start with a normal conversational response. Do not call tools for greetings, small talk, ",
    "or questions you can answer directly.\n",
    "- Use the calc tool for arithmetic and expressions.\n",
    "- Use the exec tool for shell/system tasks.\n",
    "- If the user starts a message with `/sh `, run it with `exec` exactly as written.\n",
    "- Use the browser tool when the user asks to visit/read/interact with web pages.\n",
    "- Before tool calls, briefly state what you are about to do.\n",
    "- For multi-step tasks, execute one step at a time and check results before proceeding.\n",
    "- Be careful with destructive operations, confirm with the user first.\n",
    "- Do not express surprise about sandbox vs host execution. Route changes are normal.\n",
    "- Do not suggest disabling sandbox unless the user explicitly asks for host execution or ",
    "the task cannot be completed in sandbox.\n",
    "- The UI already shows raw tool output (stdout/stderr/exit). Summarize outcomes instead.\n\n",
    "## Silent Replies\n\n",
    "When you have nothing meaningful to add after a tool call, return an empty response.\n",
);
const MINIMAL_GUIDELINES: &str = concat!(
    "## Guidelines\n\n",
    "- Be helpful, accurate, and concise.\n",
    "- If you don't know something, say so rather than making things up.\n",
    "- For coding questions, provide clear explanations with examples.\n",
);

/// Internal: build system prompt with full control over what's included.
fn build_system_prompt_full(
    tools: &ToolRegistry,
    native_tools: bool,
    project_context: Option<&str>,
    skills: &[SkillMetadata],
    identity: Option<&AgentIdentity>,
    user: Option<&UserProfile>,
    soul_text: Option<&str>,
    agents_text: Option<&str>,
    tools_text: Option<&str>,
    runtime_context: Option<&PromptRuntimeContext>,
    include_tools: bool,
    memory_text: Option<&str>,
) -> String {
    ...
}

fn append_identity_and_user_sections(
    prompt: &mut String,
    identity: Option<&AgentIdentity>,
    user: Option<&UserProfile>,
    soul_text: Option<&str>,
) {
    ...
}

fn append_project_context(prompt: &mut String, project_context: Option<&str>) {
    ...
}

fn format_node_runtime_line(node: &PromptNodeInfo) -> String {
    ...
}

fn format_nodes_runtime_section(nodes_ctx: &PromptNodesRuntimeContext) -> Option<String> {
    ...
}

const NODE_ROUTING_GUIDANCE: &str = "\
- When nodes are connected, the `exec` tool accepts an optional `node` parameter to target a specific node.\n\
- Omitting `node` runs on the session's default node (shown as [default: ...] above), or locally if none is set.\n\
- Use node telemetry (CPU, memory) to pick appropriate targets for resource-intensive tasks.\n\n";

fn append_runtime_section(
    prompt: &mut String,
    runtime_context: Option<&PromptRuntimeContext>,
    include_tools: bool,
) {
    ...
}

fn append_skills_section(prompt: &mut String, include_tools: bool, skills: &[SkillMetadata]) {
    ...
}

fn append_workspace_files_section(
    prompt: &mut String,
    agents_text: Option<&str>,
    tools_text: Option<&str>,
) {
    ...
}

fn append_memory_section(
    prompt: &mut String,
    memory_text: Option<&str>,
    tool_schemas: &[serde_json::Value],
) {
    ...
}

fn has_tool_schema(tool_schemas: &[serde_json::Value], tool_name: &str) -> bool {
    ...
}

fn append_available_tools_section(
    prompt: &mut String,
    native_tools: bool,
    tool_schemas: &[serde_json::Value],
) {
    ...
}

fn append_tool_call_guidance(
    prompt: &mut String,
    native_tools: bool,
    tool_schemas: &[serde_json::Value],
    model_id: Option<&str>,
) {
    ...
}

fn append_guidelines_section(prompt: &mut String, include_tools: bool) {
    ...
}

fn append_runtime_datetime_tail(
    prompt: &mut String,
    runtime_context: Option<&PromptRuntimeContext>,
) {
    ...
}

fn push_non_empty_runtime_field(parts: &mut Vec<String>, key: &str, value: Option<&str>) {
    ...
}

fn format_host_runtime_line(host: &PromptHostRuntimeContext) -> Option<String> {
    ...
}

fn truncate_prompt_text(text: &str, max_chars: usize) -> String {
    ...
}

fn append_truncated_text_block(
    prompt: &mut String,
    text: &str,
    max_chars: usize,
    truncated_notice: &str,
) {
    ...
}

fn format_sandbox_runtime_line(sandbox: &PromptSandboxRuntimeContext) -> String {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_fallback_prompt_includes_tool_call_format() {
    ...
}

    #[test]
    fn test_native_prompt_uses_compact_tool_list() {
    ...
}

    #[test]
    fn test_skills_injected_into_prompt() {
    ...
}

    #[test]
    fn test_no_skills_block_when_empty() {
    ...
}

    #[test]
    fn test_identity_injected_into_prompt() {
    ...
}

    #[test]
    fn test_custom_soul_injected() {
    ...
}

    #[test]
    fn test_no_identity_no_extra_lines() {
    ...
}

    #[test]
    fn test_workspace_files_injected_when_provided() {
    ...
}

    #[test]
    fn test_runtime_context_injected_when_provided() {
    ...
}

    #[test]
    fn test_runtime_context_sandbox_without_sudo_omits_sudo_hint() {
    ...
}

    #[test]
    fn test_runtime_context_no_sandbox_uses_host_only_routing() {
    ...
}

    #[test]
    fn test_runtime_context_no_sandbox_with_sudo_includes_sudo_hint() {
    ...
}

    #[test]
    fn test_runtime_context_includes_location_when_set() {
    ...
}

    #[test]
    fn test_runtime_context_includes_channel_surface_fields_when_set() {
    ...
}

    #[test]
    fn test_runtime_context_omits_location_when_none() {
    ...
}

    #[test]
    fn test_minimal_prompt_runtime_does_not_add_exec_routing_block() {
    ...
}

    #[test]
    fn test_silent_replies_section_in_tool_prompt() {
    ...
}

    #[test]
    fn test_silent_replies_not_in_minimal_prompt() {
    ...
}

    #[test]
    fn test_memory_text_injected_into_prompt() {
    ...
}

    #[test]
    fn test_memory_text_truncated_at_limit() {
    ...
}

    #[test]
    fn test_no_memory_section_without_memory_or_tools() {
    ...
}

    #[test]
    fn test_memory_text_in_minimal_prompt() {
    ...
}

    /// Helper to create a [`ToolRegistry`] with one or more named stub tools.
    fn registry_with_tools(names: &[&'static str]) -> ToolRegistry {
    ...
}

    #[test]
    fn test_memory_save_hint_injected_when_tool_registered() {
    ...
}

    #[test]
    fn test_memory_save_hint_absent_without_tool() {
    ...
}

    #[test]
    fn test_memory_search_and_save_hints_both_present() {
    ...
}

    #[test]
    fn test_datetime_tail_appended_at_end_when_runtime_time_present() {
    ...
}

    #[test]
    fn test_datetime_tail_falls_back_to_today_when_time_missing() {
    ...
}

    #[test]
    fn test_datetime_tail_not_injected_without_time_or_date() {
    ...
}

    // ── Phase 4: ModelFamily, compact schema, tool call guidance ────────

    #[test]
    fn model_family_detects_llama() {
    ...
}

    #[test]
    fn model_family_detects_qwen() {
    ...
}

    #[test]
    fn model_family_detects_mistral() {
    ...
}

    #[test]
    fn model_family_detects_others() {
    ...
}

    #[test]
    fn model_family_unknown_for_unrecognized() {
    ...
}

    #[test]
    fn compact_schema_formats_required_and_optional_params() {
    ...
}

    #[test]
    fn compact_schema_no_params_section_when_empty() {
    ...
}

    #[test]
    fn tool_call_guidance_includes_fenced_example() {
    ...
}

    #[test]
    fn tool_call_guidance_works_with_no_model() {
    ...
}

    #[test]
    fn text_mode_prompt_uses_compact_schema() {
    ...
}
}
