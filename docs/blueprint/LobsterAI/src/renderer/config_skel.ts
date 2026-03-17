// 配置类型定义
export interface AppConfig {
  // API 配置
  // 模型配置
  // 多模型提供商配置
      // API 协议格式：anthropic 为 Anthropic 兼容，openai 为 OpenAI 兼容
      /** 是否启用 Moonshot Coding Plan 模式（使用专属 Coding API 端点） */
      /** 是否启用 GLM Coding Plan 模式（使用专属 Coding API 端点） */
      /** 是否启用 Qwen Coding Plan 模式（使用专属 Coding API 端点） */
      /** 是否启用 Volcengine Coding Plan 模式（使用专属 Coding API 端点） */
  // 主题配置
  // 语言配置
  // 是否使用系统代理
  // 语言初始化标记 (用于判断是否是首次启动)
  // 应用配置
  // 快捷键配置

// 默认配置
export const defaultConfig: AppConfig = {

// 配置存储键
export const CONFIG_KEYS = {

// 模型提供商分类
export const CHINA_PROVIDERS = ['deepseek', 'moonshot', 'qwen', 'zhipu', 'minimax', 'volcengine', 'youdaozhiyun', 'stepfun', 'xiaomi', 'ollama', 'custom'] as const;
export const GLOBAL_PROVIDERS = ['openai', 'gemini', 'anthropic', 'openrouter'] as const;
export const EN_PRIORITY_PROVIDERS = ['openai', 'anthropic', 'gemini'] as const;

/**
 * 根据语言获取可见的模型提供商
 */
export const getVisibleProviders = (language: 'zh' | 'en'): readonly string[] => {
  // 开发环境下显示所有提供商
  // if (import.meta.env.DEV) {
  //   return [...CHINA_PROVIDERS, ...GLOBAL_PROVIDERS];
  // }

  // 中文 → 中国版，英文 → 国际版
  if (language === 'zh') {
  }

  // Move ollama and custom to the end, with custom last
  for (const key of ['ollama', 'custom'] as const) {
  }
