export type AnthropicApiFormat = 'anthropic' | 'openai';

export type OpenAIStreamChunk = {

function toObject(value: unknown): Record<string, unknown> {
}

function toArray(value: unknown): unknown[] {
}

function toString(value: unknown): string {
}

function toOptionalObject(value: unknown): Record<string, unknown> | null {
}

function stringifyUnknown(value: unknown): string {
}

export function normalizeProviderApiFormat(format: unknown): AnthropicApiFormat {
  if (format === 'openai') {
  }

export function mapStopReason(finishReason?: string | null): string | null {
  if (!finishReason) {
  }
  if (finishReason === 'tool_calls') {
  }
  if (finishReason === 'stop') {
  }
  if (finishReason === 'length') {
  }

export function formatSSEEvent(event: string, data: unknown): string {

function cleanSchema(schema: unknown): unknown {
}

function convertMessageToOpenAI(role: string, content: unknown): Array<Record<string, unknown>> {
}

export function anthropicToOpenAI(body: unknown): Record<string, unknown> {
const output: Record<string, unknown>;

  if (source.model !== undefined) {
  }

const messages: Array<Record<string, unknown>>;

  if (typeof system === 'string' && system) {
  }

  for (const item of sourceMessages) {
  }


  if (source.max_tokens !== undefined) {
  }
  if (source.temperature !== undefined) {
  }
  if (source.top_p !== undefined) {
  }
  if (source.stop_sequences !== undefined) {
  }
  if (source.stream !== undefined) {
  }


  if (tools.length > 0) {
  }

  if (source.tool_choice !== undefined) {
  }


export function openAIToAnthropic(body: unknown): Record<string, unknown> {

const content: Array<Record<string, unknown>>;

  if (reasoningContent) {
  }

  if (typeof textContent === 'string' && textContent) {
  }

  for (const toolCall of toolCalls) {
  }



export function buildOpenAIChatCompletionsURL(baseURL: string): string {
  if (!normalized) {
  }


  // Handle /v1, /v4 etc. versioned paths
