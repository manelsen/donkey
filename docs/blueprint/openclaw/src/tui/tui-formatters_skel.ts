import { formatRawAssistantErrorForUi } from "../agents/pi-embedded-helpers.js";
import { stripLeadingInboundMetadata } from "../auto-reply/reply/strip-inbound-meta.js";
import { stripAnsi } from "../terminal/ansi.js";
import { formatTokenCount } from "../utils/usage-format.js";
function hasControlChars(text: string): boolean;
function stripControlChars(text: string): string;
function chunkToken(token: string, maxChars: number): string[];
function isCopySensitiveToken(token: string): boolean;
function normalizeLongTokenForDisplay(token: string): string;
function redactBinaryLikeLine(line: string): string;
function isolateRtlLine(line: string): string;
function applyRtlIsolation(text: string): string;
export function sanitizeRenderableText(text: string): string;
export function resolveFinalAssistantText(params:;
export function composeThinkingAndContent(params:;
function asMessageRecord(message: unknown): Record<string, unknown> | undefined;
function resolveMessageRecord(;
function formatAssistantErrorFromRecord(record: Record<string, unknown>): string;
function collectSanitizedBlockStrings(params:;
/**
 * Extract ONLY thinking blocks from message content.
 * Model-agnostic: returns empty string if no thinking blocks exist.
 */
export function extractThinkingFromMessage(message: unknown): string;
/**
 * Extract ONLY text content blocks from message (excludes thinking).
 * Model-agnostic: works for any model with text content blocks.
 */
export function extractContentFromMessage(message: unknown): string;
function extractTextBlocks(content: unknown, opts?:;
export function extractTextFromMessage(;
export function isCommandMessage(message: unknown): boolean;
export function formatTokens(total?: number | null, context?: number | null);
export function formatContextUsageLine(params:;
export function asString(value: unknown, fallback = ""): string;
