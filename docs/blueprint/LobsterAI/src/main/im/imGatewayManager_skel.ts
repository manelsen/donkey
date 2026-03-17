/**
 * IM Gateway Manager
 * Unified manager for DingTalk, Feishu and Telegram gateways
 */

import { EventEmitter } from 'events';
import * as path from 'path';
import * as os from 'os';
import * as fs from 'fs';
import { DingTalkGateway } from './dingtalkGateway';
import { FeishuGateway } from './feishuGateway';
import { TelegramGateway } from './telegramGateway';
import { DiscordGateway } from './discordGateway';
import { NimGateway } from './nimGateway';
import { XiaomifengGateway } from './xiaomifengGateway';
import { QQGateway } from './qqGateway';
import { WecomGateway } from './wecomGateway';
import { IMChatHandler } from './imChatHandler';
import { IMCoworkHandler } from './imCoworkHandler';
import { IMStore } from './imStore';
import { getOapiAccessToken } from './dingtalkMedia';
import { fetchJsonWithTimeout } from './http';
import {
import type { Database } from 'sql.js';
import type { CoworkRunner } from '../libs/coworkRunner';
import type { CoworkStore } from '../coworkStore';

interface TelegramGetMeResponse {

interface DiscordUserResponse {

export interface IMGatewayManagerOptions {

export class IMGatewayManager extends EventEmitter {

  // Cowork dependencies

  // NIM probe mutex: serializes concurrent connectivity tests



    // Store Cowork dependencies if provided
    if (options?.coworkRunner && options?.coworkStore) {
    }

    // Forward gateway events

  /**
   * Set up event forwarding from gateways
   */
  private setupGatewayEventForwarding(): void {
  }

  /**
   * Reconnect all disconnected gateways
   * Called when network is restored via IPC event
   */
  reconnectAllDisconnected(): void {
  }

  /**
   * Initialize the manager with LLM and skills providers
   */

    // Set up message handlers for gateways

  /**
   * Set up message handlers for both gateways
   */
  private setupMessageHandlers(): void {
  }

  /**
   * Persist the notification target for a platform after receiving a message.
   */
  private persistNotificationTarget(platform: IMPlatform): void {
  }

  /**
   * Restore notification target from SQLite after gateway starts.
   */
  private restoreNotificationTarget(platform: IMPlatform): void {
  }

  /**
   * Update chat handler with current settings
   */
  private updateChatHandler(): void {
  }

  /**
   * Update or create Cowork handler
   * Always creates handler if dependencies are available (Cowork mode is always enabled for IM)
   */
  private updateCoworkHandler(): void {
  }

  // ==================== Configuration ====================

  /**
   * Get current configuration
   */
  getConfig(): IMGatewayConfig {
  }

  /**
   * Update configuration
   */
  setConfig(config: Partial<IMGatewayConfig>): void {
  }

  /**
   * Restart a specific gateway (stop then start with latest config)
   * Used for hot-reloading when credentials change at runtime.
   */

  // ==================== Status ====================

  /**
   * Get current status of all gateways
   */
  getStatus(): IMGatewayStatus {
  }

  /**
   * Test platform connectivity and readiness for conversation.
   */
const checks: IMConnectivityCheck[];

    const addCheck = (check: IMConnectivityCheck) => {

    if (missingCredentials.length > 0) {
    }



    if (enabled && !connected) {
    }


    if (connected && startedAt && testedAt - startedAt >= INBOUND_ACTIVITY_WARN_AFTER_MS) {
    }

    if (connected && lastInboundAt) {
    }

    if (lastError) {
    }

    if (platform === 'feishu') {
    }


  // ==================== Gateway Control ====================

  /**
   * Start a specific gateway
   */
  async startGateway(platform: IMPlatform): Promise<void> {
  }

  /**
   * Stop a specific gateway
   */
  async stopGateway(platform: IMPlatform): Promise<void> {
  }

  /**
   * Start all enabled gateways
   */
  async startAllEnabled(): Promise<void> {
  }

  /**
   * Stop all gateways
   */
  async stopAll(): Promise<void> {
  }

  /**
   * Check if any gateway is connected
   */
  isAnyConnected(): boolean {
  }

  /**
   * Check if a specific gateway is connected
   */
  isConnected(platform: IMPlatform): boolean {
  }

  /**
   * Send a notification message through a specific platform.
   * Uses platform-specific broadcast mechanisms.
   * Returns true if successfully sent, false if platform not connected.
   */
  async sendNotification(platform: IMPlatform, text: string): Promise<boolean> {
  }

  async sendNotificationWithMedia(platform: IMPlatform, text: string): Promise<boolean> {
  }

  private buildMergedConfig(configOverride?: Partial<IMGatewayConfig>): IMGatewayConfig {
  }

  private getMissingCredentials(platform: IMPlatform, config: IMGatewayConfig): string[] {
  }

    if (platform === 'dingtalk') {
    }

    if (platform === 'feishu') {
    }

    if (platform === 'telegram') {
    }
    if (platform === 'nim') {
    }

    if (platform === 'xiaomifeng') {
    }

    if (platform === 'wecom') {
    }

    if (platform === 'discord') {
    }

    if (platform === 'qq') {
    }


  /**
   * Test NIM connectivity.
   *
   * NIM enforces single-device login per account: if a second client logs in
   * with the same account, the first one is kicked offline. Therefore we CANNOT
   * create a temporary NimGateway alongside the main one.
   *
   * Strategy:
   * 1. If the main nimGateway is already connected → credentials are valid,
   *    return immediately.
   * 2. Otherwise, **stop the main gateway first** (if it has a stale SDK
   *    instance), then create a temporary probe instance with its own data
   *    path. After the probe completes, fully stop it, then **restart the
   *    main gateway** so normal message reception resumes.
   */
    // Fast path: if the main gateway is already connected, credentials are valid.

    // Mutex: if a previous probe is still running, wait for it to finish first
    // to avoid concurrent NIM SDK instances causing native crashes.
    if (this.nimProbePromise) {
    }

    // Wrap the actual probe in a tracked promise for mutex

  /**
   * Internal NIM probe execution (called under mutex protection).
   */
    // Stop the main gateway before probing to avoid kick-offline conflicts.
    // This is a no-op if it's not running.

    // Wait for native SDK resources to be fully released before creating a new instance.

let tmpGateway: NimGateway | null;

    // Use a unique temporary data path to avoid file-lock conflicts.




        // Also listen for loginFailed which may not always emit 'error'

      // Fully stop the temporary instance before doing anything else.
      if (tmpGateway) {
      }

      // Wait for native cleanup before restarting the main gateway.

      // Clean up the temporary data directory after a short delay.
      setTimeout(() => {
      }, 2000);

      // Restart the main gateway if the NIM config says it should be enabled
      // so that normal message reception resumes.
      // We restart regardless of probe success: even if the probe failed,
      // the main gateway was stopped and needs to be restarted if enabled.
      if (nimConfig.enabled) {
      }

  private resolveFeishuDomain(domain: string, Lark: any): any {
  }

let timeoutId: NodeJS.Timeout | null;
      if (timeoutId) {
      }

  private getStartedAtMs(platform: IMPlatform, status: IMGatewayStatus): number | null {
  }

  private getLastInboundAt(platform: IMPlatform, status: IMGatewayStatus): number | null {
  }

  private getLastOutboundAt(platform: IMPlatform, status: IMGatewayStatus): number | null {
  }

  private getLastError(platform: IMPlatform, status: IMGatewayStatus): string | null {
  }

  private calculateVerdict(checks: IMConnectivityCheck[]): IMConnectivityVerdict {
  }
