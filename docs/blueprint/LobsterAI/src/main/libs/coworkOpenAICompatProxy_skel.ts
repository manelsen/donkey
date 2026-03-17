import http from 'http';
import { BrowserWindow, session } from 'electron';
import {
  type OpenAIStreamChunk,
import type { ScheduledTaskStore, ScheduledTaskInput } from '../scheduledTaskStore';
import type { Scheduler } from './scheduler';

export type OpenAICompatUpstreamConfig = {

export type OpenAICompatProxyTarget = 'local' | 'sandbox';

export type OpenAICompatProxyStatus = {

type ToolCallState = {

type StreamState = {

type UpstreamAPIType = 'chat_completions' | 'responses';

type ResponsesFunctionCallState = {

type ResponsesStreamContext = {


let proxyServer: http.Server | null;
let proxyPort: number | null;
let upstreamConfig: OpenAICompatUpstreamConfig | null;
let lastProxyError: string | null;

// --- Scheduled task API dependencies ---
interface ScheduledTaskDeps {
let scheduledTaskDeps: ScheduledTaskDeps | null;

export function setScheduledTaskDeps(deps: ScheduledTaskDeps): void {

function toOptionalObject(value: unknown): Record<string, unknown> | null {
}

function toString(value: unknown): string {
}

function toArray(value: unknown): unknown[] {
}

function toNumber(value: unknown): number | null {
}

function stringifyUnknown(value: unknown): string {
}

function normalizeFunctionArguments(value: unknown): string {
}

function normalizeScheduledTaskWorkingDirectory(value: unknown): string {
}

function normalizeToolCallExtraContent(toolCallObj: Record<string, unknown>): unknown {
}

function cacheToolCallExtraContent(toolCallId: string, extraContent: unknown): void {
}

function cacheToolCallExtraContentFromOpenAIToolCalls(toolCalls: unknown): void {
}

function cacheToolCallExtraContentFromOpenAIResponse(body: unknown): void {
}

function hydrateOpenAIRequestToolCalls(
  for (const message of messages) {
  }

function createAnthropicErrorBody(message: string, type = 'api_error'): Record<string, unknown> {
}

function extractErrorMessage(raw: string): string {
}

function estimateTokenCountForText(text: string): number {
}

function estimateTokenCountFromUnknown(value: unknown): number {
}

function estimateAnthropicCountTokensRequestInputTokens(requestBody: unknown): number {
}

function resolveUpstreamAPIType(provider?: string): UpstreamAPIType {
}

function buildOpenAIResponsesURL(baseURL: string): string {
}

function buildUpstreamTargetUrls(baseURL: string, apiType: UpstreamAPIType): string[] {
}

function extractTextFromChatContent(content: unknown): string {
}

function convertUserChatContentToResponsesInput(content: unknown): Array<Record<string, unknown>> {
}

function normalizeResponsesToolsFromChat(toolsInput: unknown): Array<Record<string, unknown>> {
}

function normalizeResponsesToolChoiceFromChat(toolChoice: unknown): unknown {
}

function convertChatCompletionsRequestToResponsesRequest(
const request: Record<string, unknown>;
const input: Array<Record<string, unknown>>;
const instructions: string[];
  const unresolvedFunctionCalls = new Map<string, { name: string; hasOutput: boolean }>();

  if (chatRequest.model !== undefined) {
  }
  if (chatRequest.stream !== undefined) {
  }
  if (chatRequest.temperature !== undefined) {
  }
  if (chatRequest.top_p !== undefined) {
  }
  if (normalizedTools.length > 0) {
  }
  if (chatRequest.tool_choice !== undefined) {
  }

  if (maxOutputTokens !== null) {
  }

    if (!messageObj) {
    }

    if (role === 'system') {
    }

    if (role === 'tool') {
    }

    if (role === 'assistant') {
    }

    if (userParts.length > 0) {
    }

  if (instructions.length > 0) {
  }

  for (const messageItem of input) {
  }

    if (callInfo.hasOutput) {
    }
    // OpenAI Responses requires each historical function_call to have a matching output.
    // When upstream tool execution fails before producing a tool_result, auto-close it here.



function normalizeToolName(value: unknown): string {
}

function filterOpenAIToolsForProvider(
  if (provider !== 'openai') {
  }

  if (tools.length === 0) {
  }

    // OpenAI path should use skills by reading SKILL.md via normal tools, not Skill tool.

  if (filteredTools.length !== tools.length) {
  }

/**
 * MiniMax API only accepts 'system', 'user', and 'assistant' roles.
 * OpenAI's newer API uses 'developer' role which MiniMax doesn't recognize.
 * This function remaps 'developer' to 'system' for MiniMax compatibility.
 */
function remapMessageRolesForMiniMax(
  if (provider !== 'minimax') {
  }

  if (messages.length === 0) {
  }

  for (const message of messages) {
  }

function extractMaxTokensRange(errorMessage: string): { min: number; max: number } | null {
}

function clampMaxTokensFromError(

  if (!range) {
  }


  if (nextValue === currentMaxTokens) {
  }


function shouldUseMaxCompletionTokensForModel(model: unknown): boolean {
}

function normalizeMaxTokensFieldForOpenAIProvider(
  if (provider !== 'openai') {
  }

/**
 * Merge multiple system messages into a single one at the beginning.
 * Some OpenAI-compatible providers (e.g. MiniMax) reject requests containing
 * more than one system message, returning error 2013 "invalid chat setting".
 * This is safe for all providers since the semantic meaning is preserved.
 */
function mergeSystemMessagesForProvider(
  if (messages.length === 0) {
  }

const systemTexts: string[];
const nonSystemMessages: unknown[];
  for (const msg of messages) {
  }

  // Only rewrite if there are 2+ system messages; otherwise leave as-is
  if (systemTexts.length <= 1) {
  }

const merged: unknown[];

function isMaxTokensUnsupportedError(errorMessage: string): boolean {
}

/**
 * Detect errors where the upstream model does not support tool calling.
 * Ollama returns messages like "registry.ollama.ai/library/gemma3:1b does not support tools".
 */
function isToolsUnsupportedError(errorMessage: string): boolean {
}

/**
 * Strip tools and tool_choice from an OpenAI-format request.
 * Returns true if tools were actually removed.
 */
function stripToolsFromRequest(openAIRequest: Record<string, unknown>): boolean {
}

function convertMaxTokensToMaxCompletionTokens(

function writeJSON(

function readRequestBody(req: http.IncomingMessage): Promise<string> {
}

function createStreamState(): StreamState {
}

function createResponsesStreamContext(): ResponsesStreamContext {
}

function resolveResponsesObject(body: unknown): Record<string, unknown> {
}

function extractResponsesReasoningText(itemObj: Record<string, unknown>): string {
}

function detectResponsesFinishReason(responseObj: Record<string, unknown>): string {
}

function convertResponsesToOpenAIResponse(body: unknown): Record<string, unknown> {
}

function cacheToolCallExtraContentFromResponsesResponse(body: unknown): void {
}

function emitSSE(res: http.ServerResponse, event: string, data: Record<string, unknown>): void {
}

function closeCurrentBlockIfNeeded(res: http.ServerResponse, state: StreamState): void {
}

function ensureMessageStart(
  if (state.hasMessageStart) {
  }




function ensureThinkingBlock(res: http.ServerResponse, state: StreamState): void {
}

function ensureTextBlock(res: http.ServerResponse, state: StreamState): void {
}

function ensureToolUseBlock(

  if (state.currentBlockType === 'tool_use' && state.activeToolIndex === index) {
  }


const contentBlock: Record<string, unknown>;

  if (toolCall.extraContent !== undefined) {
  }



function emitMessageDelta(


function processOpenAIChunk(

  if (!choice) {
  }


  if (deltaReasoning) {
  }

  if (delta?.content) {
  }

    for (const item of delta.tool_calls) {
    }

  if (choice.finish_reason) {
  }

function parseSSEPacket(packet: string): { event: string; payload: string } {
}

function findSSEPacketBoundary(
  if (!match || typeof match.index !== 'number') {
  }


function extractResponsesFunctionCallMetadata(
  const extraContent = itemObj ? normalizeToolCallExtraContent(itemObj) : undefined;

function registerResponsesFunctionCallState(

  if (!callState && metadata.itemId) {
  }
  if (!callState && metadata.outputIndex !== null) {
  }

  if (!callState) {
  }

  if (metadata.callId) {
  }
  if (metadata.itemId) {
  }
  if (metadata.name) {
  }
  if (metadata.extraContent !== undefined) {
  }


function syncToolCallStateWithResponsesFunctionCall(
  if (callState.callId) {
  }
  if (callState.name) {
  }
  if (callState.extraContent !== undefined) {
  }
  if (toolCall.id && toolCall.extraContent !== undefined) {
  }

function emitResponsesFunctionCallChunk(

const functionObj: Record<string, unknown>;
  if (options.includeName && toolCall.name) {
  }

  if (argumentsText) {
  }



function emitResponsesFunctionCallMetadataOnce(
  if (callState.metadataEmitted) {
  }
  if (!callState.name) {
  }


function emitResponsesFunctionCallArgumentsOnce(
  if (callState.emitted) {
  }

  if (!resolvedArguments) {
  }


function emitResponsesCompletedFunctionCalls(


const payloadObj: Record<string, unknown>;
    if (itemOutputIndex !== null) {
    }



function emitResponsesFallbackContent(
  if (!message) {
  }

  if (reasoning) {
  }

  if (typeof messageContent === 'string' && messageContent) {
  }

    if (!toolCallObj || !functionObj) {
    }

const payloadObj: Record<string, unknown>;

function processResponsesStreamEvent(

  if (responseObjFromPayload) {
  }

  if (eventType === 'response.created') {
  }

  if (eventType === 'response.output_text.delta' || eventType === 'response.output.delta') {
  }

    if (thinkingDelta) {
    }

  if (eventType === 'response.output_item.added' || eventType === 'response.output_item.done') {
  }

  if (eventType === 'response.function_call_arguments.delta') {
  }

  if (eventType === 'response.function_call_arguments.done') {
  }

  if (eventType === 'response.completed') {
  }

async function handleResponsesStreamResponse(

  if (!upstreamResponse.body) {
  }



    if (!state.hasMessageStart) {
    }
    if (!state.hasMessageStop) {
    }

  while (true) {
  }

  if (sawDoneMarker) {
  }


async function handleChatCompletionsStreamResponse(

  if (!upstreamResponse.body) {
  }



    if (!state.hasMessageStart) {
    }
    if (!state.hasMessageStop) {
    }


  while (true) {
  }

  if (sawDoneMarker) {
  }


async function handleCreateScheduledTask(
  if (!scheduledTaskDeps) {
  }



  // Validate required fields
  if (!input.schedule?.type) {
  }
  if (input.schedule.type === 'cron' && !input.schedule.expression) {
  }
  if (input.schedule.type === 'at' && !input.schedule.datetime) {
  }

  // Validate: "at" type must be in the future
  if (input.schedule.type === 'at' && input.schedule.datetime) {
  }

  // Validate: expiresAt must not be in the past
  if (input.expiresAt) {
  }

  // Build ScheduledTaskInput with defaults
const taskInput: ScheduledTaskInput;


    // Notify renderer to refresh task list


async function handleListScheduledTasks(
  if (!scheduledTaskDeps) {
  }

async function handleGetScheduledTask(
  if (!scheduledTaskDeps) {
  }
    if (!task) {
    }

async function handleUpdateScheduledTask(
  if (!scheduledTaskDeps) {
  }

  // Verify task exists first
  if (!existing) {
  }



  // Validate schedule if provided
  if (input.schedule !== undefined) {
  }

  // Validate expiresAt if provided
  if (input.expiresAt !== undefined && input.expiresAt !== null) {
  }

  // Normalize workingDirectory if provided
const updateInput: Partial<ScheduledTaskInput>;
  if (input.workingDirectory !== undefined) {
  }

    if (!task) {
    }

    // Notify renderer to refresh task list


async function handleDeleteScheduledTask(
  if (!scheduledTaskDeps) {
  }

  if (!existing) {
  }


    // Notify renderer to refresh task list


async function handleToggleScheduledTask(
  if (!scheduledTaskDeps) {
  }



  if (typeof input.enabled !== 'boolean') {
  }

    if (!task) {
    }

    // Notify renderer to refresh task list


async function handleRequest(

  if (method === 'GET' && url.pathname === '/healthz') {
  }

  // Scheduled task API

  if (method === 'GET' && url.pathname === TASK_LIST_PATH) {
  }
  if (method === 'POST' && url.pathname === TASK_LIST_PATH) {
  }

  // Toggle check BEFORE item check (more specific path)
  if (method === 'POST' && toggleMatch) {
  }

  if (itemMatch) {
  }

  if (method === 'POST' && url.pathname === '/api/event_logging/batch') {
  }

  if (method === 'POST' && url.pathname === '/v1/messages/count_tokens') {
  }

  if (method !== 'POST' || url.pathname !== '/v1/messages') {
  }

  if (!upstreamConfig) {
  }



  if (!openAIRequest.model) {
  }

  // Force-remap model name to the user-configured upstream model.
  // The Claude Agent SDK may emit internal model names (e.g. claude-haiku-4-5-20251001)
  // for probe/warmup requests, which non-Anthropic providers don't recognize.
  if (upstreamConfig.provider && upstreamConfig.provider !== 'anthropic' && upstreamConfig.provider !== 'openai') {
  }

  if (upstreamAPIType === 'chat_completions') {
  }

  // Some providers (e.g. MiniMax) reject requests with multiple system messages.
  // Merge all system messages into one before sending to these providers.
  // This fix applies to both chat_completions and responses API types.



const headers: Record<string, string>;
  if (upstreamConfig.apiKey) {
  }




  if (!upstreamResponse.ok) {
  }


  if (stream) {
  }


  if (upstreamAPIType === 'responses') {
  }



export const __openAICompatProxyTestUtils = {

export async function startCoworkOpenAICompatProxy(): Promise<void> {
  if (proxyServer) {
  }

        if (!res.headersSent) {
        }


      if (!addr || typeof addr === 'string') {
      }


export async function stopCoworkOpenAICompatProxy(): Promise<void> {
  if (!proxyServer) {
  }


      if (error) {
      }

export function configureCoworkOpenAICompatProxy(config: OpenAICompatUpstreamConfig): void {

export function getCoworkOpenAICompatProxyBaseURL(target: OpenAICompatProxyTarget = 'local'): string | null {
  if (!proxyServer || !proxyPort) {
  }
  const host = target === 'sandbox' ? SANDBOX_HOST : LOCAL_HOST;

/**
 * Get the proxy base URL for internal API use (scheduled tasks, etc.).
 * Unlike getCoworkOpenAICompatProxyBaseURL which is for the LLM proxy,
 * this always returns the local proxy URL regardless of API format.
 */
export function getInternalApiBaseURL(): string | null {

export function getCoworkOpenAICompatProxyStatus(): OpenAICompatProxyStatus {
