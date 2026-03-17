import { randomUUID } from "node:crypto";
import type { Component, SelectItem, TUI } from "@mariozechner/pi-tui";
import {
import type { SessionsPatchResult } from "../gateway/protocol/index.js";
import { formatRelativeTimestamp } from "../infra/format-time/format-relative.ts";
import { normalizeAgentId } from "../routing/session-key.js";
import { helpText, parseCommand } from "./commands.js";
import type { ChatLog } from "./components/chat-log.js";
import {
import type { GatewayChatClient } from "./gateway-chat.js";
import { sanitizeRenderableText } from "./tui-formatters.js";
import { formatStatusSummary } from "./tui-status-summary.js";
import type {
type CommandHandlerContext = {
function isBtwCommand(text: string): boolean;
export function createCommandHandlers(context: CommandHandlerContext);
