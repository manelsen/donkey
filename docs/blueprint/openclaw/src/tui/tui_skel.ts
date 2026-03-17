import {
import { resolveAgentIdByWorkspacePath, resolveDefaultAgentId } from "../agents/agent-scope.js";
import { loadConfig, type OpenClawConfig } from "../config/config.js";
import {
import { getSlashCommands } from "./commands.js";
import { ChatLog } from "./components/chat-log.js";
import { CustomEditor } from "./components/custom-editor.js";
import { GatewayChatClient } from "./gateway-chat.js";
import { editorTheme, theme } from "./theme/theme.js";
import { createCommandHandlers } from "./tui-command-handlers.js";
import { createEventHandlers } from "./tui-event-handlers.js";
import { formatTokens } from "./tui-formatters.js";
import { createLocalShellRunner } from "./tui-local-shell.js";
import { createOverlayHandlers } from "./tui-overlays.js";
import { createSessionActions } from "./tui-session-actions.js";
import type {
import { buildWaitingStatusMessage, defaultWaitingPhrases } from "./tui-waiting.js";
export { resolveFinalAssistantText } from "./tui-formatters.js";
export function createEditorSubmitHandler(params:;
export function shouldEnableWindowsGitBashPasteFallback(params?:;
export function createSubmitBurstCoalescer(params:;
export function resolveTuiSessionKey(params:;
export function resolveInitialTuiAgentId(params:;
export function resolveGatewayDisconnectState(reason?: string):;
export function createBackspaceDeduper(params?:;
export function isIgnorableTuiStopError(error: unknown): boolean;
export function stopTuiSafely(stop: () => void): void;
type CtrlCAction = "clear" | "warn" | "exit";
export function resolveCtrlCAction(params:;
export async function runTui(opts: TuiOptions);
