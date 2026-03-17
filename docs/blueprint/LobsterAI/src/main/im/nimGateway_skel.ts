/**
 * NIM (NetEase IM) Gateway
 * Manages NIM SDK V2 connection for receiving and sending messages
 * Adapted from openclaw-nim for Electron main process
 */

import { EventEmitter } from 'events';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { app } from 'electron';
// eslint-disable-next-line @typescript-eslint/no-require-imports
import type { V2NIM } from 'nim-web-sdk-ng/dist/nodejs/nim';
import {
import {
import { parseMediaMarkers, stripMediaMarkers } from './dingtalkMediaParser';
import { NimQChatClient, QChatInboundMessage } from './nimQChatClient';

// Message deduplication cache

/** Maximum characters per text message */

/**
 * NIM message type mapping from V2NIMMessageType enum
 */
type NimMessageType = 'text' | 'image' | 'audio' | 'video' | 'file' | 'geo' | 'notification' | 'custom' | 'tip' | 'robot' | 'unknown';

function convertMessageType(v2Type: number): NimMessageType {
}

/**
 * Parse conversationId format: {appId}|{type}|{targetId}
 */
function parseConversationId(conversationId: string): { sessionType: NimSessionType; targetId: string } {
}

/**
 * Build conversationId using SDK utility or manual fallback
 */
function buildConversationId(conversationIdUtil: any, accountId: string, sessionType: NimSessionType = 'p2p'): string {
}

/**
 * Get SDK data directory
 */
function getSdkDataPath(account: string): string {
}

/**
 * Split long text into chunks
 */
function splitMessageIntoChunks(text: string, maxLength: number = MAX_MESSAGE_LENGTH): string[] {
}

/**
 * Check if a team message should be processed based on teamPolicy
 * @param params.teamPolicy The team message policy from config
 * @param params.teamAllowlist List of allowed team IDs (when policy is 'allowlist')
 * @param params.teamId The team ID from the message
 * @param params.forcePushAccountIds Account IDs that were @-mentioned in the message
 * @param params.botAccount The bot's account ID
 */
function isTeamMessageAllowed(params: {
}

export class NimGateway extends EventEmitter {

  /**
   * Bound callback references so we can properly remove them from SDK services.
   * Without these, each start/stop cycle leaks native event listeners, and
   * callbacks may fire on freed C++ objects → segfault.
   */

  /**
   * Lifecycle mutex: serializes start() and stop() calls so that rapid
   * toggle (ON → OFF → ON) never causes concurrent native SDK init/uninit.
   */

  /**
   * Flag to indicate that a stop() has been requested (or is in-flight).
   * Used to suppress reconnect timers that were scheduled before stop() was called.
   */

  /**
   * QChat client instance for circle group messages
   */

  constructor() {
  }

  /**
   * Get current gateway status
   */
  getStatus(): NimGatewayStatus {
  }

  /**
   * Check if gateway is connected
   */
  isConnected(): boolean {
  }

  /**
   * Check whether the native SDK instance is instantiated.
   */
  isRunning(): boolean {
  }

  /**
   * Check whether a reconnect attempt is pending.
   */
  isReconnecting(): boolean {
  }

  /**
   * Update runtime config without restarting the gateway.
   * Used for hot-updating non-credential fields like accountWhitelist.
   */
  updateConfig(partial: Partial<NimConfig>): void {
  }

  /**
   * Public method for external reconnection triggers
   */
  reconnectIfNeeded(): void {
  }

  /**
   * Schedule a reconnection attempt with exponential backoff.
   *
   * IMPORTANT: The reconnect callback goes through the public stop()/start()
   * methods which serialize via lifecyclePromise. It never calls uninit()
   * directly, preventing native SDK races.
   */
  private scheduleReconnect(delayMs: number): void {
  }

  /**
   * Set message callback
   */

  /**
   * Start NIM gateway
   * @param config NIM configuration
   * @param options Additional start options
   * @param options.appDataPathOverride Override the SDK data path (useful for isolated probe instances)
   */
  async start(config: NimConfig, options?: { appDataPathOverride?: string }): Promise<void> {
  }

  /**
   * Internal start implementation (called under lifecycle mutex).
   */
    if (this.v2Client) {
    }
    // Always keep config for reconnection

    if (!config.enabled) {
    }

    if (!config.appKey || !config.account || !config.token) {
    }




      // Initialize NIM SDK using new NIM() for multi-instance support


      // Verify services are available
      if (!this.v2Client.V2NIMLoginService || !this.v2Client.V2NIMMessageService) {
      }

      // Create bound callbacks so we can remove them in stopInternal().
      // Each callback checks this.v2Client as a staleness guard: if uninit()
      // was called and cleanup() nulled the reference, the callback becomes
      // a harmless no-op instead of touching freed native memory.
        for (const msg of messages) {
        }

        // V2NIMLoginStatus: 0=LOGOUT, 1=LOGINED, 2=LOGINING
        if (loginStatus === 1) {
        }

        // Schedule reconnect after kicked offline

        // Schedule reconnect after login failure

        // Schedule reconnect after unexpected disconnect

      // Register callbacks using bound references

      // Login (don't await - status will be updated via events)
      // But we need to catch potential rejections
          // Error code 191002 (operation cancelled) can be safely ignored as login will retry
          // For non-cancellation errors, emit 'error' so that connectivity tests
          // (and any other listener) are notified even if the 'loginFailed' SDK
          // event does not fire for this particular rejection reason.
          if (error?.code !== 191002) {
          }

      // Initialize status (will be updated by loginStatus callback)
      // Note: do NOT reset config here – it was set at the top of start()


  /**
   * Stop NIM gateway
   */
  async stop(): Promise<void> {
  }

  /**
   * Internal stop implementation (called under lifecycle mutex).
   */
    // Cancel any pending reconnect timer
    if (this.reconnectTimer) {
    }

    // Stop QChat client first
    if (this.qchatClient) {
    }

    if (!this.v2Client) {
    }


    // STEP 1: Remove event listeners BEFORE destroy() so that native threads
    // that fire callbacks during teardown find no JS listeners to invoke.
    // This is the key fix for the "more stop/start cycles → higher crash
    // probability" issue: without removal, stale callbacks accumulate and
    // may be invoked on freed native objects.
      if (this.v2Client?.V2NIMMessageService && this.boundOnReceiveMessages) {
      }
      if (this.v2Client?.V2NIMLoginService) {
      }

    // Null out bound references so even if a late native callback somehow
    // still fires, the staleness guard (if (!this.v2Client) return) in
    // each callback will make it a no-op.

    // STEP 2: Logout and destroy the SDK instance.
      if (this.v2Client) {
      }

    // STEP 3: Clean up JavaScript references immediately
    
    // Update status

    
    // Wait for native SDK resources to be fully released before allowing
    // the next init(). 1000ms gives the C++ destructor and OS enough time
    // to tear down sockets, threads and memory-mapped files.
    // Increased from 500ms to 1000ms for extra safety on repeated cycles.

  /**
   * Clean up internal references (does NOT clear config to allow reconnection)
   */
  private cleanup(): void {
  }

  /**
   * Fetch the display name for a team via V2NIMTeamService.getTeamInfo().
   * teamType: 1 = advanced team (高级群), 2 = super team (超大群).
   * Falls back to the provided fallbackId on any error.
   */
      if (!nim?.V2NIMTeamService) {
      }
      // If local cache miss, try fetching from cloud

  /**
   * Fetch QChat channel display name.
   * Falls back to channelId on any error.
   */

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
   * Parse V2 message attachment fields
   * 与 openclaw-nim/src/client.ts 的 parseV2Attachment 一致
   */
  private parseV2Attachment(msg: any): { url?: string; name?: string; size?: number; width?: number; height?: number; duration?: number } | undefined {
  }

  /**
   * Handle incoming V2 message from SDK
   * 支持 text、image、audio、video、file 消息类型
   */

      // Only process online messages (messageSource === 1).
      // V2NIMMessageSource: 0=unknown, 1=online, 2=offline, 3=roaming.
      // Offline (2) and roaming (3) messages are historical records pulled
      // during sync; we skip them to avoid re-processing old conversations.
const messageSource: number;
      if (messageSource !== 1) {
      }

      // Ignore messages from self
      if (this.config && senderId === this.config.account) {
      }

      // Whitelist filtering: if accountWhitelist is set, only process messages from whitelisted accounts
      if (this.config?.accountWhitelist) {
      }

      // Deduplication

      // 打印原始消息结构，便于确认 SDK 字段名



      // 支持的消息类型：text, image, audio, video, file
const supportedTypes: NimMessageType[];


      // Handle team messages: only process if bot is @-mentioned and policy allows
      if (isTeam) {
      }

      // 构建消息内容和媒体附件
const attachments: IMMediaAttachment[];

      if (msgType === 'text') {
      }

      // Mark P2P message as read so the sender sees the "read" receipt
      // and the conversation unread count is cleared on the server side.
      // Note: Only P2P messages support read receipts, team messages do not.
      if (isP2P && this.v2Client?.V2NIMMessageService) {
      }

      // P2P: 直接使用消息自带的昵称字段，无需额外 API 调用
      // V2 SDK 字段可能是 fromNick / senderNick / nickname，都尝试一下
      // 打印原始 msg 的所有 key，便于确认真实字段名（仅 debug 模式）
      // For team messages, fetch the real group name via V2NIMTeamService.
      // conversationId format: {appId}|{type}|{teamId}, type=2 for team, 3 for superTeam.
      const teamTypeNum = sessionType === 'superTeam' ? 2 : 1;

      // Create IMMessage
const message: IMMessage;



      // Create reply function with media support
      // For team messages, reply to the team with @-mention; for P2P, reply to sender
      const replyFn = async (text: string) => {

        if (isTeam) {
        }

      // Store last sender for notifications

      // Emit message event

      // Call message callback if set
      if (this.onMessageCallback) {
      }

  /**
   * Send a text message to a target account
   */
    if (!this.v2Client?.V2NIMMessageService || !this.v2Client?.V2NIMMessageCreator) {
    }

    if (!message) {
    }



  /**
   * Send long text with auto-splitting
   */

    for (const chunk of chunks) {
    }

  /**
   * Send a media file message to a target account
   */
    if (!this.v2Client?.V2NIMMessageService || !this.v2Client?.V2NIMMessageCreator) {
    }


  /**
   * Send reply with media marker parsing
   * 解析文本中的媒体标记（如 ![image](/path/to/img.png)），
   * 先发送纯文本部分，再逐个发送媒体文件。
   * 与 Telegram/DingTalk/Feishu Gateway 的 replyFn 行为一致。
   */
    // 1. 解析媒体标记

    if (markers.length === 0) {
    }


    // 2. 先发送去除标记后的文本（如果有）
      // 文本和第一个媒体之间的间隔

    // 3. 逐个发送媒体文件
    for (let i = 0; i < markers.length; i++) {
    }

  /**
   * Send a reply to a team message with quote and forcePush @-mention
   * @param teamId The team ID to send to
   * @param text The reply text
   * @param originalMsg The original message to quote/reply to
   * @param originalSenderId The original sender's account ID (for @-mention)
   * @param sessionType The session type ('team' or 'superTeam')
   */
    if (!this.v2Client?.V2NIMMessageService || !this.v2Client?.V2NIMMessageCreator) {
    }

    // Parse media markers first

    if (markers.length > 0) {
    }

  /**
   * Send text reply to a team message with quote and forcePush
   */

    for (let i = 0; i < chunks.length; i++) {
    }

  /**
   * Send media file to a team
   */
    if (!this.v2Client?.V2NIMMessageService || !this.v2Client?.V2NIMMessageCreator) {
    }



  /**
   * Get the current notification target for persistence.
   */
  getNotificationTarget(): string | null {
  }

  /**
   * Restore notification target from persisted state.
   */
  setNotificationTarget(senderId: string): void {
  }

  /**
   * Send a notification message to the last known sender
   */
  async sendNotification(text: string): Promise<void> {
  }

  /**
   * Send a notification message with media support to the last known sender
   */
  async sendNotificationWithMedia(text: string): Promise<void> {
  }

  /**
   * Clean up downloaded media files (called periodically)
   */
  cleanupMediaFiles(): void {
  }

  // ==================== QChat (Circle Groups) Support ====================

  /**
   * Activate QChat subscription after IM login succeeds
   */






  /**
   * Handle incoming QChat message
   */
      // Skip messages from self
      if (msg.senderAccid === this.config?.account) {
      }

      // Only process @-mentioned messages
      if (!msg.wasMentioned) {
      }

      // Apply whitelist if configured
      if (this.config?.accountWhitelist) {
      }



      // Fetch real channel name (fall back to channelId).
      // senderNick comes directly from the QChat message payload; use accid as fallback.
      const senderName = (msg.senderNick && msg.senderNick.trim()) ? msg.senderNick.trim() : msg.senderAccid;

const imMessage: IMMessage;

      // Create reply function for QChat
      const replyFn = async (text: string) => {


      // Store last sender for notifications

      // Emit message event

      // Call message callback if set
      if (this.onMessageCallback) {
      }

  /**
   * Send reply to a QChat channel
   */
    if (!this.qchatClient) {
    }

    // Parse media markers

    if (markers.length > 0) {
    }

  /**
   * Send long text to QChat with auto-splitting
   */

    for (const chunk of chunks) {
    }
