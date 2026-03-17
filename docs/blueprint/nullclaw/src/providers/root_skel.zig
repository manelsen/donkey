const std = @import("std");
const json_util = @import("../json_util.zig");
const http_util = @import("../http_util.zig");

// Re-export all provider sub-modules
pub const anthropic = @import("anthropic.zig");
pub const openai = @import("openai.zig");
pub const ollama = @import("ollama.zig");
pub const gemini = @import("gemini.zig");
pub const vertex = @import("vertex.zig");
pub const openrouter = @import("openrouter.zig");
pub const compatible = @import("compatible.zig");
pub const reliable = @import("reliable.zig");
pub const router = @import("router.zig");
pub const sse = @import("sse.zig");
pub const claude_cli = @import("claude_cli.zig");
pub const codex_cli = @import("codex_cli.zig");
pub const openai_codex = @import("openai_codex.zig");
pub const runtime_bundle = @import("runtime_bundle.zig");
pub const api_error_details = @import("api_error_details.zig");

// Extracted sub-modules
pub const scrub = @import("scrub.zig");
pub const api_key = @import("api_key.zig");
pub const factory = @import("factory.zig");
pub const helpers = @import("helpers.zig");

// Re-exports from scrub.zig
pub const scrubSecretPatterns = scrub.scrubSecretPatterns;
pub const scrubToolOutput = scrub.scrubToolOutput;
pub const sanitizeApiError = scrub.sanitizeApiError;
pub const setApiErrorLimitOverride = scrub.setApiErrorLimitOverride;
pub const clearLastApiErrorDetail = api_error_details.clear;
pub const setLastApiErrorDetail = api_error_details.set;
pub const snapshotLastApiErrorDetail = api_error_details.snapshot;

// Re-exports from api_key.zig
pub const resolveApiKey = api_key.resolveApiKey;
pub const resolveApiKeyFromConfig = api_key.resolveApiKeyFromConfig;

// Re-exports from factory.zig
pub const ProviderKind = factory.ProviderKind;
pub const classifyProvider = factory.classifyProvider;
pub const detectProviderByApiKey = factory.detectProviderByApiKey;
pub const compatibleProviderUrl = factory.compatibleProviderUrl;
pub const compatibleProviderDisplayName = factory.compatibleProviderDisplayName;
pub const ProviderHolder = factory.ProviderHolder;

// Re-exports from helpers.zig
pub const complete = helpers.complete;
pub const completeWithSystem = helpers.completeWithSystem;
pub const providerUrl = helpers.providerUrl;
pub const buildRequestBody = helpers.buildRequestBody;
pub const buildRequestBodyWithSystem = helpers.buildRequestBodyWithSystem;
pub const isReasoningModel = helpers.isReasoningModel;
pub const appendGenerationFields = helpers.appendGenerationFields;
pub const appendGeminiThinkingConfig = helpers.appendGeminiThinkingConfig;
pub const appendVertexThinkingConfig = helpers.appendVertexThinkingConfig;
pub const convertToolsOpenAI = helpers.convertToolsOpenAI;
pub const serializeMessageContent = helpers.serializeMessageContent;
pub const serializeContentPart = helpers.serializeContentPart;
pub const convertToolsAnthropic = helpers.convertToolsAnthropic;
pub const curlPostTimed = helpers.curlPostTimed;
pub const curlPostFormTimed = helpers.curlPostFormTimed;
pub const extractContent = helpers.extractContent;
pub const SplitThinkContent = helpers.SplitThinkContent;
pub const splitThinkContent = helpers.splitThinkContent;
pub const stripThinkBlocks = helpers.stripThinkBlocks;
pub const normalizeOpenAiReasoningEffort = helpers.normalizeOpenAiReasoningEffort;

// Direct re-exports from utility modules
pub const appendJsonString = json_util.appendJsonString;
pub const curlPost = http_util.curlPost;

// ════════════════════════════════════════════════════════════════════════════
// Core Types
// ════════════════════════════════════════════════════════════════════════════

/// Level of detail for image processing.
pub const ImageDetail = enum {

/// A single content part in a multimodal message.

    pub const ImageUrl = struct {

    pub const ImageBase64 = struct {

/// Create a text content part.
pub fn makeTextPart(text: []const u8) ContentPart

/// Create an image URL content part.
pub fn makeImageUrlPart(url: []const u8) ContentPart

/// Create a base64-encoded image content part.
pub fn makeBase64ImagePart(data: []const u8, media_type: []const u8) ContentPart

/// Roles a message can have in a conversation.
pub const Role = enum {

/// A single message in a conversation.
pub const ChatMessage = struct {
    /// Optional name (for tool results).
    /// Tool call ID this message responds to.
    /// Optional multimodal content parts (images, etc.). When set, providers
    /// serialize these instead of the plain `content` field.

/// A tool call requested by the LLM.
pub const ToolCall = struct {

/// Token usage stats from a provider response.
pub const TokenUsage = struct {

/// An LLM response that may contain text, tool calls, or both.
pub const ChatResponse = struct {
    /// Effective provider that produced this response (set by wrappers such as ReliableProvider).
    /// Optional reasoning/thinking content from models that support it (e.g. Claude extended thinking).
    /// True when the LLM wants to invoke at least one tool.

// ════════════════════════════════════════════════════════════════════════════
// Streaming Types
// ════════════════════════════════════════════════════════════════════════════

/// A single chunk of streamed output.
pub const StreamChunk = struct {
    /// Create a text delta chunk with estimated token count.

/// Callback invoked for each streaming chunk.
pub const StreamCallback = *const fn (ctx: *anyopaque, chunk: StreamChunk) void;

/// Result of a streaming chat call (accumulated after stream completes).
pub const StreamChatResult = struct {

/// Tool specification for function-calling APIs.
pub const ToolSpec = struct {
    /// JSON schema for the tool's parameters.

/// Request payload for provider chat calls.
pub const ChatRequest = struct {
    /// Optional upstream session identifier (for example, the NullClaw session key).
    /// Stateful providers can use this to scope their own resume/context handling.
    /// Max seconds to wait for the HTTP response (curl --max-time). 0 = no limit.
    /// Reasoning effort for reasoning models (o1, o3, gpt-5*). null = don't send.

/// A single tool result message in a conversation.
pub const ToolResultMessage = struct {

/// Kind discriminator for ConversationMessage.
pub const ConversationMessageKind = enum { chat, assistant_tool_calls, tool_results };
/// A conversation message that can be a plain chat, assistant tool calls, or tool results.
// ════════════════════════════════════════════════════════════════════════════
// Provider Interface (vtable-based polymorphism)
// ════════════════════════════════════════════════════════════════════════════
/// Provider interface. Zig equivalent of ZeroClaw's `trait Provider`.
/// Uses vtable-based polymorphism for runtime dispatch.
        /// Simple one-shot chat: system prompt + user message.