import type { OpenClawConfig } from "../config/config.js";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { normalizeLegacyOnboardAuthChoice } from "./auth-choice-legacy.js";
import { applyAuthChoiceApiProviders } from "./auth-choice.apply.api-providers.js";
import { normalizeApiKeyTokenProviderAuthChoice } from "./auth-choice.apply.api-providers.js";
import { applyAuthChoiceOAuth } from "./auth-choice.apply.oauth.js";
import { applyAuthChoiceLoadedPluginProvider } from "./auth-choice.apply.plugin-provider.js";
import type { AuthChoice, OnboardOptions } from "./onboard-types.js";
export type ApplyAuthChoiceParams = {
export type ApplyAuthChoiceResult = {
export async function applyAuthChoice(;
