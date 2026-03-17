import { join } from 'path';
import { app } from 'electron';
import type { SqliteStore } from '../sqliteStore';
import type { CoworkApiConfig } from './coworkConfigStore';
import {
  type OpenAICompatProxyTarget,
import { normalizeProviderApiFormat, type AnthropicApiFormat } from './coworkFormatTransform';

// Qwen Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)
// Volcengine Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)
// Moonshot/Kimi Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)

type ProviderModel = {

type ProviderConfig = {

type AppConfig = {

export type ApiConfigResolution = {

// Store getter function injected from main.ts

export function setStoreGetter(getter: () => SqliteStore | null): void {

const getStore = (): SqliteStore | null => {
  if (!storeGetter) {
  }

export function getClaudeCodePath(): string {
  if (app.isPackaged) {
  }

  // In development, try to find the SDK in the project root node_modules
  // app.getAppPath() might point to dist-electron or other build output directories
  // We need to look in the project root
  // If appPath ends with dist-electron, go up one level


type MatchedProvider = {

function getEffectiveProviderApiFormat(providerName: string, apiFormat: unknown): AnthropicApiFormat {
}

function providerRequiresApiKey(providerName: string): boolean {
}

function resolveMatchedProvider(appConfig: AppConfig): { matched: MatchedProvider | null; error?: string } {
}

export function resolveCurrentApiConfig(target: OpenAICompatProxyTarget = 'local'): ApiConfigResolution {
  if (!sqliteStore) {
  }

  if (!appConfig) {
  }

  if (!matched) {
  }


  if (matched.apiFormat === 'anthropic') {
  }

  if (!proxyStatus.running) {
  }


  if (!proxyBaseURL) {
  }


export function getCurrentApiConfig(target: OpenAICompatProxyTarget = 'local'): CoworkApiConfig | null {

export function buildEnvForConfig(config: CoworkApiConfig): Record<string, string> {


