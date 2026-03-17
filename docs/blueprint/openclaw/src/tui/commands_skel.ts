import type { SlashCommand } from "@mariozechner/pi-tui";
import { listChatCommands, listChatCommandsForConfig } from "../auto-reply/commands-registry.js";
import { formatThinkingLevels, listThinkingLevelLabels } from "../auto-reply/thinking.js";
import type { OpenClawConfig } from "../config/types.js";
export type ParsedCommand = {
export type SlashCommandOptions = {
function createLevelCompletion(;
export function parseCommand(input: string): ParsedCommand;
export function getSlashCommands(options: SlashCommandOptions =;
export function helpText(options: SlashCommandOptions =;
