import { loginOpenAICodex, type OAuthCredentials } from "@mariozechner/pi-ai/oauth";
import type { RuntimeEnv } from "../runtime.js";
import type { WizardPrompter } from "../wizard/prompts.js";
import { createVpsAwareOAuthHandlers } from "./oauth-flow.js";
import {
export async function loginOpenAICodexOAuth(params:;
