import { parseAgentSessionKey } from "../sessions/session-key-utils.js";
import { asString, extractTextFromMessage, isCommandMessage } from "./tui-formatters.js";
import { TuiStreamAssembler } from "./tui-stream-assembler.js";
import type { AgentEvent, BtwEvent, ChatEvent, TuiStateAccess } from "./tui-types.js";
type EventHandlerChatLog = {
type EventHandlerTui = {
type EventHandlerBtwPresenter = {
type EventHandlerContext = {
export function createEventHandlers(context: EventHandlerContext);
