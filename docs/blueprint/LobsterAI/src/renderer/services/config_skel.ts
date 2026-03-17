import { AppConfig, CONFIG_KEYS, defaultConfig } from '../config';
import { localStore } from './store';

const getFixedProviderApiFormat = (providerKey: string): 'anthropic' | 'openai' | null => {
  if (providerKey === 'openai' || providerKey === 'gemini' || providerKey === 'stepfun' || providerKey === 'youdaozhiyun') {
  }
  if (providerKey === 'anthropic') {
  }

const normalizeProviderBaseUrl = (providerKey: string, baseUrl: unknown): string => {
  if (typeof baseUrl !== 'string') {
  }

  if (providerKey !== 'gemini') {
  }




const normalizeProviderApiFormat = (providerKey: string, apiFormat: unknown): 'anthropic' | 'openai' => {
  if (fixed) {
  }
  if (apiFormat === 'openai') {
  }

const normalizeProvidersConfig = (providers: AppConfig['providers']): AppConfig['providers'] => {
  if (!providers) {
  }


class ConfigService {

  async init() {
  }

  getConfig(): AppConfig {
  }

  async updateConfig(newConfig: Partial<AppConfig>) {
  }

  getApiConfig() {
  }

export const configService = new ConfigService(); 
