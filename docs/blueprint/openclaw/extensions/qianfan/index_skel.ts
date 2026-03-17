import { emptyPluginConfigSchema, type OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { buildQianfanProvider } from "../../src/agents/models-config.providers.static.js";
import { applyQianfanConfig, QIANFAN_DEFAULT_MODEL_REF } from "../../src/commands/onboard-auth.js";
import { createProviderApiKeyAuthMethod } from "../../src/plugins/provider-api-key-auth.js";
export default qianfanPlugin;
