import {
import { ensureAuthProfileStore, listProfilesForProvider } from "../../src/agents/auth-profiles.js";
import { MINIMAX_OAUTH_MARKER } from "../../src/agents/model-auth-markers.js";
import {
import {
import { fetchMinimaxUsage } from "../../src/infra/provider-usage.fetch.js";
import { createProviderApiKeyAuthMethod } from "../../src/plugins/provider-api-key-auth.js";
import { loginMiniMaxPortalOAuth, type MiniMaxRegion } from "./oauth.js";
function getDefaultBaseUrl(region: MiniMaxRegion): string;
function apiModelRef(modelId: string): string;
function portalModelRef(modelId: string): string;
function isModernMiniMaxModel(modelId: string): boolean;
function buildPortalProviderCatalog(params:;
function resolveApiCatalog(ctx: ProviderCatalogContext);
function resolvePortalCatalog(ctx: ProviderCatalogContext);
function createOAuthHandler(region: MiniMaxRegion);
export default minimaxPlugin;
