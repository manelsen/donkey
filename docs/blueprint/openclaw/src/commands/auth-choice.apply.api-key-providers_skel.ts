import { ensureAuthProfileStore, resolveAuthProfileOrder } from "../agents/auth-profiles.js";
import { normalizeApiKeyInput, validateApiKeyInput } from "./auth-choice.api-key.js";
import { ensureApiKeyFromOptionEnvOrPrompt } from "./auth-choice.apply-helpers.js";
import type { ApplyAuthChoiceParams, ApplyAuthChoiceResult } from "./auth-choice.apply.js";
import {
import type { SecretInputMode } from "./onboard-types.js";
type ApiKeyProviderConfigApplier = (
type ApplyProviderDefaultModel = (args: {
type ApplyApiKeyProviderParams = {
export async function applyLiteLlmApiKeyProvider(;
