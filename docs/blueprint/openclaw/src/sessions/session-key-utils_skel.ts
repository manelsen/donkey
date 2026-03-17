export type ParsedAgentSessionKey = {
export type SessionKeyChatType = "direct" | "group" | "channel" | "unknown";
/**
 * Parse agent-scoped session keys in a canonical, case-insensitive way.
 * Returned values are normalized to lowercase for stable comparisons/routing.
 */
export function parseAgentSessionKey(;
/**
 * Best-effort chat-type extraction from session keys across canonical and legacy formats.
 */
export function deriveSessionChatType(sessionKey: string | undefined | null): SessionKeyChatType;
export function isCronRunSessionKey(sessionKey: string | undefined | null): boolean;
export function isCronSessionKey(sessionKey: string | undefined | null): boolean;
export function isSubagentSessionKey(sessionKey: string | undefined | null): boolean;
export function getSubagentDepth(sessionKey: string | undefined | null): number;
export function isAcpSessionKey(sessionKey: string | undefined | null): boolean;
export function resolveThreadParentSessionKey(;
