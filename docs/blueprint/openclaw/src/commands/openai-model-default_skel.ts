import type { OpenClawConfig } from "../config/config.js";
import { ensureModelAllowlistEntry } from "./model-allowlist.js";
export const OPENAI_DEFAULT_MODEL = "openai/gpt-5.1-codex";
export function applyOpenAIProviderConfig(cfg: OpenClawConfig): OpenClawConfig;
export function applyOpenAIConfig(cfg: OpenClawConfig): OpenClawConfig;
