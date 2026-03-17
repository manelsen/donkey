import { confirm, select } from "@clack/prompts";
import type { RuntimeEnv } from "../runtime.js";
import { stylePromptHint, stylePromptMessage } from "../terminal/prompt-style.js";
import { guardCancel } from "./onboard-helpers.js";
export type DoctorOptions = {
export type DoctorPrompter = {
export function createDoctorPrompter(params:;
