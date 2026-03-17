import {
import {
import { suggestOAuthProfileIdForLegacyDefault } from "../../src/agents/auth-profiles/repair.js";
import type { AuthProfileStore } from "../../src/agents/auth-profiles/types.js";
import { normalizeModelCompat } from "../../src/agents/model-compat.js";
import { formatCliCommand } from "../../src/cli/command-format.js";
import { parseDurationMs } from "../../src/cli/parse-duration.js";
import {
import { buildTokenProfileId, validateAnthropicSetupToken } from "../../src/commands/auth-token.js";
import { applyAuthProfileConfig } from "../../src/commands/onboard-auth.js";
import { fetchClaudeUsage } from "../../src/infra/provider-usage.fetch.js";
import { createProviderApiKeyAuthMethod } from "../../src/plugins/provider-api-key-auth.js";
import type { ProviderAuthResult } from "../../src/plugins/types.js";
import { normalizeSecretInput } from "../../src/utils/normalize-secret-input.js";
function cloneFirstTemplateModel(params:;
function resolveAnthropic46ForwardCompatModel(params:;
function resolveAnthropicForwardCompatModel(;
function matchesAnthropicModernModel(modelId: string): boolean;
function buildAnthropicAuthDoctorHint(params:;
async function runAnthropicSetupToken(ctx: ProviderAuthContext): Promise<ProviderAuthResult>;
async function runAnthropicSetupTokenNonInteractive(ctx:;
export default anthropicPlugin;
