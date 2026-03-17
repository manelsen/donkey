import {
import { ensureAuthProfileStore, listProfilesForProvider } from "../../src/agents/auth-profiles.js";
import { QWEN_OAUTH_MARKER } from "../../src/agents/model-auth-markers.js";
import { refreshQwenPortalCredentials } from "../../src/providers/qwen-portal-oauth.js";
import { loginQwenPortalOAuth } from "./oauth.js";
function normalizeBaseUrl(value: string | undefined): string;
function buildModelDefinition(params:;
function buildProviderCatalog(params:;
function resolveCatalog(ctx: ProviderCatalogContext);
export default qwenPortalPlugin;
