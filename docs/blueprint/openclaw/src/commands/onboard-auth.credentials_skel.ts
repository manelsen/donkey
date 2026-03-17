import fs from "node:fs";
import path from "node:path";
import type { OAuthCredentials } from "@mariozechner/pi-ai";
import { resolveOpenClawAgentDir } from "../agents/agent-paths.js";
import { upsertAuthProfile } from "../agents/auth-profiles.js";
import { resolveStateDir } from "../config/paths.js";
import {
import { KILOCODE_DEFAULT_MODEL_REF } from "../providers/kilocode-shared.js";
import { PROVIDER_ENV_VARS } from "../secrets/provider-env-vars.js";
import { normalizeSecretInput } from "../utils/normalize-secret-input.js";
import type { SecretInputMode } from "./onboard-types.js";
export { CLOUDFLARE_AI_GATEWAY_DEFAULT_MODEL_REF } from "../agents/cloudflare-ai-gateway.js";
export {
export { KILOCODE_DEFAULT_MODEL_REF };
const resolveAuthAgentDir;
export type ApiKeyStorageOptions = {
function buildEnvSecretRef(id: string): SecretRef;
function parseEnvSecretRef(value: string): SecretRef | null;
function resolveProviderDefaultEnvSecretRef(provider: string): SecretRef;
function resolveApiKeySecretInput(;
export function buildApiKeyCredential(;
export type WriteOAuthCredentialsOptions = {
/** Resolve real path, returning null if the target doesn't exist. */
function safeRealpathSync(dir: string): string | null;
function resolveSiblingAgentDirs(primaryAgentDir: string): string[];
export async function writeOAuthCredentials(;
export async function setAnthropicApiKey(;
export async function setOpenaiApiKey(;
export async function setGeminiApiKey(;
export async function setMinimaxApiKey(;
export async function setMoonshotApiKey(;
export async function setKimiCodingApiKey(;
export async function setVolcengineApiKey(;
export async function setByteplusApiKey(;
export async function setSyntheticApiKey(;
export async function setVeniceApiKey(;
export const ZAI_DEFAULT_MODEL_REF = "zai/glm-5";
export const XIAOMI_DEFAULT_MODEL_REF = "xiaomi/mimo-v2-flash";
export const OPENROUTER_DEFAULT_MODEL_REF = "openrouter/auto";
export const HUGGINGFACE_DEFAULT_MODEL_REF = "huggingface/deepseek-ai/DeepSeek-R1";
export const TOGETHER_DEFAULT_MODEL_REF = "together/moonshotai/Kimi-K2.5";
export const LITELLM_DEFAULT_MODEL_REF = "litellm/claude-opus-4-6";
export const VERCEL_AI_GATEWAY_DEFAULT_MODEL_REF = "vercel-ai-gateway/anthropic/claude-opus-4.6";
export async function setZaiApiKey(;
export async function setXiaomiApiKey(;
export async function setOpenrouterApiKey(;
export async function setCloudflareAiGatewayConfig(;
export async function setLitellmApiKey(;
export async function setVercelAiGatewayApiKey(;
export async function setOpencodeZenApiKey(;
export async function setOpencodeGoApiKey(;
async function setSharedOpencodeApiKey(;
export async function setTogetherApiKey(;
export async function setHuggingfaceApiKey(;
export function setQianfanApiKey(;
export function setModelStudioApiKey(;
export function setXaiApiKey(key: SecretInput, agentDir?: string, options?: ApiKeyStorageOptions);
export async function setMistralApiKey(;
export async function setKilocodeApiKey(;
