import { getChannelPlugin } from "../channels/plugins/index.js";
import type { ChannelId, ChannelMessageActionName } from "../channels/plugins/types.js";
import type { OutboundDeliveryResult } from "../infra/outbound/deliver.js";
import { formatGatewaySummary, formatOutboundDeliverySummary } from "../infra/outbound/format.js";
import type { MessageActionRunResult } from "../infra/outbound/message-action-runner.js";
import { formatTargetDisplay } from "../infra/outbound/target-resolver.js";
import { getTerminalTableWidth, renderTable } from "../terminal/table.js";
import { isRich, theme } from "../terminal/theme.js";
import { shortenText } from "./text-format.js";
const resolveChannelLabel;
function extractMessageId(payload: unknown): string | null;
export type MessageCliJsonEnvelope = {
export function buildMessageCliJson(result: MessageActionRunResult): MessageCliJsonEnvelope;
type FormatOpts = {
function renderObjectSummary(payload: unknown, opts: FormatOpts): string[];
function renderMessageList(messages: unknown[], opts: FormatOpts, emptyLabel: string): string[];
function renderMessagesFromPayload(payload: unknown, opts: FormatOpts): string[] | null;
function renderPinsFromPayload(payload: unknown, opts: FormatOpts): string[] | null;
function extractDiscordSearchResultsMessages(results: unknown): unknown[] | null;
function renderReactions(payload: unknown, opts: FormatOpts): string[] | null;
export function formatMessageCliText(result: MessageActionRunResult): string[];
