import type { TUI } from "@mariozechner/pi-tui";
import type { SessionsPatchResult } from "../gateway/protocol/index.js";
import {
import type { ChatLog } from "./components/chat-log.js";
import type { GatewayAgentsList, GatewayChatClient } from "./gateway-chat.js";
import { asString, extractTextFromMessage, isCommandMessage } from "./tui-formatters.js";
import type { SessionInfo, TuiOptions, TuiStateAccess } from "./tui-types.js";
type SessionActionBtwPresenter = {
type SessionActionContext = {
type SessionInfoDefaults = {
type SessionInfoEntry = SessionInfo & {
export function createSessionActions(context: SessionActionContext);
