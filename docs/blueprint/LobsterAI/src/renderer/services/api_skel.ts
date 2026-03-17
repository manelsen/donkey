import { store } from '../store';
import { configService } from './config';
import { ChatMessagePayload, ChatUserMessageInput, ImageAttachment } from '../types/chat';

// Qwen Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)
// Volcengine Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)
// Moonshot Coding Plan 专属端点 (OpenAI 兼容和 Anthropic 兼容)

export interface ApiConfig {

export class ApiError extends Error {

// 生成唯一的请求 ID

class ApiService {

  setConfig(config: ApiConfig) {
  }

  cancelOngoingRequest() {
  }

  private cleanup() {
  }

  private normalizeApiFormat(apiFormat: unknown): 'anthropic' | 'openai' {
  }

  private buildOpenAICompatibleChatCompletionsUrl(baseUrl: string, provider: string): string {
  }

  private buildOpenAIResponsesUrl(baseUrl: string): string {
  }

  private shouldUseOpenAIResponsesApi(provider: string): boolean {
  }

  private buildImageHint(images?: ImageAttachment[]): string {
  }

  private mergeContentWithImageHint(content: string, images?: ImageAttachment[]): string {
  }

  private extractImageData(image: ImageAttachment): { mimeType: string; data: string } | null {
  }

  private formatOpenAIMessage(message: ChatMessagePayload, supportsImages: boolean) {
  }

  private formatOpenAIResponsesInputMessage(message: ChatMessagePayload, supportsImages: boolean) {
  }

  private extractResponsesOutputText(payload: any): string {
  }

  private formatAnthropicMessage(message: ChatMessagePayload, supportsImages: boolean) {
  }

  private providerRequiresApiKey(provider: string): boolean {
  }

  // 检测当前选择的模型属于哪个 provider
  private detectProvider(modelId: string, providerHint?: string): string {
  }

  // 获取指定 provider 的配置
  private getProviderConfig(provider: string): ApiConfig | null {
  }

    if (!this.config) {
    }

const userMessage: ChatUserMessageInput;

    // 尝试获取模型对应 provider 的配置
    if (providerConfig) {
    }


    // 根据 API 协议格式决定调用方式：
    // - anthropic: Anthropic 兼容协议 (/v1/messages)
    // - openai: OpenAI 兼容协议 (OpenAI provider uses /v1/responses)

    if (!useOpenAIFormat) {
    }


  // Anthropic API 调用


      // Anthropic 需要将 history 中的 system 消息分离出来


const requestBody: any;

      // 添加 system 消息
      if (systemMessages.length > 0) {
      }

      // 检测是否是 thinking 模型

      if (isThinkingModel) {
      }


        // 设置流式监听器

          for (const line of lines) {
          }

          if (!fullContent) {
          }




        // 发起流式请求
          if (!response.ok && !aborted) {
          }
          if (!aborted) {
          }
      if (error instanceof ApiError) {
      }

  // OpenAI 兼容 API 调用 (OpenAI, DeepSeek, etc.)


const userMessage: ChatMessagePayload;


        // 设置流式监听器

          for (const rawLine of lines) {
          }

          if (!fullContent) {
          }




const headers: Record<string, string>;
        if (config.apiKey) {
        }

const requestBody: Record<string, unknown>;
        if (useResponsesApi && systemInstructions) {
        }

          if (!response.ok && !aborted) {
          }
          if (!aborted) {
          }
      if (error instanceof ApiError) {
      }

export const apiService = new ApiService();
