/**
 * Feishu/Lark Gateway
 * Manages WebSocket connection for receiving messages
 * Adapted from im-gateway for Electron main process
 */

import { EventEmitter } from 'events';
import * as fs from 'fs';
import * as path from 'path';
import {
import {
import { parseMediaMarkers } from './dingtalkMediaParser';
import { stringifyAsciiJson } from './jsonEncoding';
import { isSystemProxyEnabled, resolveSystemProxyUrl } from '../libs/systemProxy';

// Message deduplication cache

// Feishu message event structure
interface FeishuMessageEvent {

export class FeishuGateway extends EventEmitter {

  constructor() {
  }

  /**
   * Get current gateway status
   */
  getStatus(): FeishuGatewayStatus {
  }

  /**
   * Check if gateway is connected
   */
  isConnected(): boolean {
  }

  /**
   * Check whether the WebSocket gateway is instantiated.
   */
  isRunning(): boolean {
  }

  /**
   * Public method for external reconnection triggers (e.g., network events)
   */
  reconnectIfNeeded(): void {
  }

  /**
   * Set message callback
   */

  /**
   * Start Feishu gateway
   */
  async start(config: FeishuConfig): Promise<void> {
  }

  /**
   * Stop Feishu gateway
   */
  async stop(): Promise<void> {
  }

  /**
   * Resolve domain to Lark SDK domain
   */
  private resolveDomain(domain: string, Lark: any): any {
  }

  /**
   * Probe bot info
   */
const response: any;

      if (response.code !== 0) {
      }


  /**
   * Add a reaction emoji to a message (best-effort, non-blocking)
   */
const response: any;
      if (response.code !== 0) {
      }

  /**
   * Check if message was already processed (deduplication)
   */
  private isMessageProcessed(messageId: string): boolean {
  }

  /**
   * Clean up expired messages from cache
   */
  private cleanupProcessedMessages(): void {
  }

  /**
   * Parse message content
   */
  private parseMessageContent(content: string, messageType: string): string {
  }

  /**
   * Parse post (rich text) content
   */
  private parsePostContent(content: string): string {
  }

  /**
   * Check if bot was mentioned
   */
  private checkBotMentioned(event: FeishuMessageEvent): boolean {
  }

  /**
   * Strip bot mention from text
   */
  private stripBotMention(text: string, mentions?: FeishuMessageEvent['message']['mentions']): string {
  }

  /**
   * Parse Feishu message event
   */
  private parseMessageEvent(event: FeishuMessageEvent): FeishuMessageContext {
  }

  /**
   * Resolve receive_id_type
   */
  private resolveReceiveIdType(target: string): 'open_id' | 'user_id' | 'chat_id' {
  }

  /**
   * Send text message
   */

    if (replyToMessageId) {
    }


    if (response.code !== 0) {
    }

  /**
   * Build markdown card
   */
  private buildMarkdownCard(text: string): Record<string, unknown> {
  }

  /**
   * Send card message
   */

    if (replyToMessageId) {
    }


    if (response.code !== 0) {
    }

  /**
   * Send message (auto-select format based on config)
   */


    if (renderMode === 'card') {
    }

  /**
   * Send image message
   */
    const content = stringifyAsciiJson({ image_key: imageKey });


    if (replyToMessageId) {
    }

    if (response.code !== 0) {
    }

  /**
   * Send file message
   */
    const content = stringifyAsciiJson({ file_key: fileKey });


    if (replyToMessageId) {
    }

    if (response.code !== 0) {
    }

  /**
   * Send audio message
   */


    if (replyToMessageId) {
    }

    if (response.code !== 0) {
    }

  /**
   * Upload and send media from file path
   * @param customFileName - 从 Markdown 解析出的自定义文件名（如 [今日新闻](file.txt) 中的"今日新闻"）
   */
    // Resolve path


    // 使用自定义文件名或从路径提取，保留原始扩展名
    const fileName = customFileName ? `${customFileName}${ext}` : originalFileName;


      // Upload image
      if (!result.success || !result.imageKey) {
      }
      // Upload audio
      if (!result.success || !result.fileKey) {
      }
      // Upload as file (including video - Feishu video requires cover image, send as file for simplicity)
      if (!result.success || !result.fileKey) {
      }

  /**
   * Send message with media support - detects and uploads media from text
   */
    // Parse media markers from text


    if (markers.length === 0) {
    }

    // Upload and send each media
    for (const marker of markers) {
    }

    // Send the text message (keep full text for context)

  /**
   * Handle inbound message
   */
    // In group chat, only respond when bot is mentioned
    if (ctx.chatType === 'group' && !ctx.mentionedBot) {
    }

    // Download media attachments if present
    if (ctx.mediaKey && ctx.mediaType && this.restClient) {
    }

    // Create IMMessage
const message: IMMessage;

    // 打印完整的输入消息日志

    // Create reply function with media support
    const replyFn = async (text: string) => {
      // 打印完整的输出消息日志


    // Store last chat ID for notifications

    // Emit message event

    // Add processing reaction (fire-and-forget)

    // Call message callback if set
    if (this.onMessageCallback) {
    }

  /**
   * Get the current notification target for persistence.
   */
  getNotificationTarget(): string | null {
  }

  /**
   * Restore notification target from persisted state.
   */
  setNotificationTarget(chatId: string): void {
  }

  /**
   * Send a notification message to the last known chat.
   */
  async sendNotification(text: string): Promise<void> {
  }

  /**
   * Send a notification message with media support to the last known chat.
   */
  async sendNotificationWithMedia(text: string): Promise<void> {
  }
