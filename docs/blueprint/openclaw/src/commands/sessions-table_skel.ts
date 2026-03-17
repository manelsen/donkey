import { DEFAULT_MODEL, DEFAULT_PROVIDER } from "../agents/defaults.js";
import { resolveConfiguredModelRef } from "../agents/model-selection.js";
import type { SessionEntry } from "../config/sessions.js";
import type { OpenClawConfig } from "../config/types.openclaw.js";
import { resolveSessionModelRef } from "../gateway/session-utils.js";
import { formatTimeAgo } from "../infra/format-time/format-relative.ts";
import { parseAgentSessionKey } from "../routing/session-key.js";
import { theme } from "../terminal/theme.js";
export type SessionDisplayRow = {
export type SessionDisplayDefaults = {
export const SESSION_KEY_PAD = 26;
export const SESSION_AGE_PAD = 9;
export const SESSION_MODEL_PAD = 14;
export function toSessionDisplayRows(store: Record<string, SessionEntry>): SessionDisplayRow[];
export function resolveSessionDisplayDefaults(cfg: OpenClawConfig): SessionDisplayDefaults;
export function resolveSessionDisplayModel(;
function truncateSessionKey(key: string): string;
export function formatSessionKeyCell(key: string, rich: boolean): string;
export function formatSessionAgeCell(updatedAt: number | null | undefined, rich: boolean): string;
export function formatSessionModelCell(model: string | null | undefined, rich: boolean): string;
export function formatSessionFlagsCell(;
