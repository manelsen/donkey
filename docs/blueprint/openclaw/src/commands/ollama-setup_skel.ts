import { upsertAuthProfileWithLock } from "../agents/auth-profiles/upsert-with-lock.js";
import { OLLAMA_DEFAULT_BASE_URL } from "../agents/ollama-defaults.js";
import {
import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import { WizardCancelledError, type WizardPrompter } from "../wizard/prompts.js";
import { isRemoteEnvironment } from "./oauth-env.js";
import { applyAgentDefaultModelPrimary } from "./onboard-auth.config-shared.js";
import { openUrl } from "./onboard-helpers.js";
import type { OnboardMode, OnboardOptions } from "./onboard-types.js";
export { OLLAMA_DEFAULT_BASE_URL } from "../agents/ollama-defaults.js";
export const OLLAMA_DEFAULT_MODEL = "glm-4.7-flash";
function normalizeOllamaModelName(value: string | undefined): string | undefined;
function isOllamaCloudModel(modelName: string | undefined): boolean;
function formatOllamaPullStatus(status: string):;
type OllamaCloudAuthResult = {
/** Check if the user is signed in to Ollama cloud via /api/me. */
async function checkOllamaCloudAuth(baseUrl: string): Promise<OllamaCloudAuthResult>;
type OllamaPullChunk = {
type OllamaPullFailureKind = "http" | "no-body" | "chunk-error" | "network";
type OllamaPullResult =
async function pullOllamaModelCore(params:;
/** Pull a model from Ollama, streaming progress updates. */
async function pullOllamaModel(;
async function pullOllamaModelNonInteractive(;
function buildOllamaModelsConfig(;
function applyOllamaProviderConfig(;
async function storeOllamaCredential(agentDir?: string): Promise<void>;
/**
 * Interactive: prompt for base URL, discover models, configure provider.
 * Model selection is handled by the standard model picker downstream.
 */
export async function promptAndConfigureOllama(params:;
/** Non-interactive: auto-discover models and configure provider. */
export async function configureOllamaNonInteractive(params:;
/** Pull the configured default Ollama model if it isn't already available locally. */
export async function ensureOllamaModelPulled(params:;
