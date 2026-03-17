import type { ApiKeyCredential, AuthProfileCredential } from "../agents/auth-profiles/types.js";
import { upsertAuthProfileWithLock } from "../agents/auth-profiles/upsert-with-lock.js";
import {
import type { OpenClawConfig } from "../config/config.js";
import type {
import type { WizardPrompter } from "../wizard/prompts.js";
import { applyAuthProfileConfig } from "./auth-profile-config.js";
export {
export function applyProviderDefaultModel(cfg: OpenClawConfig, modelRef: string): OpenClawConfig;
function buildOpenAICompatibleSelfHostedProviderConfig(params:;
type OpenAICompatibleSelfHostedProviderSetupParams = {
type OpenAICompatibleSelfHostedProviderPromptResult = {
function buildSelfHostedProviderAuthResult(;
export async function promptAndConfigureOpenAICompatibleSelfHostedProvider(;
export async function promptAndConfigureOpenAICompatibleSelfHostedProviderAuth(;
export async function discoverOpenAICompatibleSelfHostedProvider<;
function buildMissingNonInteractiveModelIdMessage(params:;
function buildSelfHostedProviderCredential(params:;
export async function configureOpenAICompatibleSelfHostedProviderNonInteractive(params:;
