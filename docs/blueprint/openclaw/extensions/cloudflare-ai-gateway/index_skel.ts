import { emptyPluginConfigSchema, type OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { upsertAuthProfile } from "../../src/agents/auth-profiles.js";
import { ensureAuthProfileStore, listProfilesForProvider } from "../../src/agents/auth-profiles.js";
import {
import { resolveNonEnvSecretRefApiKeyMarker } from "../../src/agents/model-auth-markers.js";
import {
import { ensureApiKeyFromOptionEnvOrPrompt } from "../../src/commands/auth-choice.apply-helpers.js";
import { buildApiKeyCredential } from "../../src/commands/onboard-auth.credentials.js";
import {
import type { SecretInput } from "../../src/config/types.secrets.js";
import { coerceSecretRef } from "../../src/config/types.secrets.js";
import { normalizeOptionalSecretInput } from "../../src/utils/normalize-secret-input.js";
function resolveApiKeyFromCredential(;
function resolveMetadataFromCredential(;
function buildCloudflareConfigPatch(params:;
async function resolveCloudflareGatewayMetadataInteractive(ctx:;
export default cloudflareAiGatewayPlugin;
