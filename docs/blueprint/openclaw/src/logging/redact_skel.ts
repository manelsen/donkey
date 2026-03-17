import type { OpenClawConfig } from "../config/config.js";
import { compileConfigRegex } from "../security/config-regex.js";
import { resolveNodeRequireFromMeta } from "./node-require.js";
import { replacePatternBounded } from "./redact-bounded.js";
export type RedactSensitiveMode = "off" | "tools";
type RedactOptions = {
function normalizeMode(value?: string): RedactSensitiveMode;
function parsePattern(raw: string): RegExp | null;
function resolvePatterns(value?: string[]): RegExp[];
function maskToken(token: string): string;
function redactPemBlock(block: string): string;
function redactMatch(match: string, groups: string[]): string;
function redactText(text: string, patterns: RegExp[]): string;
function resolveConfigRedaction(): RedactOptions;
export function redactSensitiveText(text: string, options?: RedactOptions): string;
export function redactToolDetail(detail: string): string;
export function getDefaultRedactPatterns(): string[];
