import { readSnakeCaseParamRaw } from "./param-key.js";
export type PollCreationParamKind = "string" | "stringArray" | "number" | "boolean";
export type PollCreationParamDef = {
export const POLL_CREATION_PARAM_DEFS: Record<string, PollCreationParamDef> = {
export type PollCreationParamName = keyof typeof POLL_CREATION_PARAM_DEFS;
export const POLL_CREATION_PARAM_NAMES = Object.keys(POLL_CREATION_PARAM_DEFS);
function readPollParamRaw(params: Record<string, unknown>, key: string): unknown;
export function resolveTelegramPollVisibility(params:;
export function hasPollCreationParams(params: Record<string, unknown>): boolean;
