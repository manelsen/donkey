export type SessionStateValue = "idle" | "processing" | "waiting";
export type SessionState = {
export type ToolCallRecord = {
export type SessionRef = {
export const diagnosticSessionStates = new Map<string, SessionState>();
export function pruneDiagnosticSessionStates(now = Date.now(), force = false): void;
function resolveSessionKey(;
function findStateBySessionId(sessionId: string): SessionState | undefined;
export function getDiagnosticSessionState(ref: SessionRef): SessionState;
export function getDiagnosticSessionStateCountForTest(): number;
export function resetDiagnosticSessionStateForTest(): void;
