import { emptyPluginConfigSchema, type OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { buildXiaomiProvider } from "../../src/agents/models-config.providers.static.js";
import { applyXiaomiConfig, XIAOMI_DEFAULT_MODEL_REF } from "../../src/commands/onboard-auth.js";
import { PROVIDER_LABELS } from "../../src/infra/provider-usage.shared.js";
import { createProviderApiKeyAuthMethod } from "../../src/plugins/provider-api-key-auth.js";
export default xiaomiPlugin;
