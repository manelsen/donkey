/**
 * IM Cowork Handler
 * Adapter that enables IM (DingTalk/Feishu/Telegram) to use CoworkRunner for tool-enabled AI execution
 */

import { EventEmitter } from 'events';
import fs from 'fs';
import path from 'path';
import type { PermissionResult } from '@anthropic-ai/claude-agent-sdk';
import type { CoworkRunner, PermissionRequest } from '../libs/coworkRunner';
import type { CoworkStore, CoworkMessage } from '../coworkStore';
import type { IMStore } from './imStore';
import type { IMMessage, IMPlatform, IMMediaAttachment } from './types';
import { buildIMMediaInstruction } from './imMediaInstruction';

interface MessageAccumulator {

interface PendingIMPermission {


export interface IMCoworkHandlerOptions {

export class IMCoworkHandler extends EventEmitter {

  // Track active sessions' message accumulation

  // Track which sessions are created by IM (to filter events)

  constructor(options: IMCoworkHandlerOptions) {
  }

  /**
   * Set up event listeners for CoworkRunner
   */
  private setupEventListeners(): void {
  }

  /**
   * Process an incoming IM message using CoworkRunner
   */
  async processMessage(message: IMMessage): Promise<string> {
  }



    // Start or continue session
    if (session && session.systemPrompt !== systemPrompt) {
    }
    if (!hasAvailableSkills) {
    }

    // 打印完整的输入消息日志

    const onSessionStartError = (error: unknown) => {

    if (isActive) {
    }


  /**
   * Get or create a Cowork session for an IM conversation
   */
    if (forceNewSession) {
    }

    // Check existing mapping
    const existing = forceNewSession ? null : this.imStore.getSessionMapping(imConversationId, platform);
    if (existing) {
    }

    // Create new Cowork session

    // Create new Cowork session

    if (!selectedWorkspaceRoot) {
    }


    // Save mapping


  /**
   * Build a human-readable session title based on platform and sender identity.
   *
   * NIM title rules:
   *   - P2P direct:  "云信-P2P-{senderName|senderId}"
   *   - Team group:  "云信-群聊-{groupName|teamId}"
   *   - QChat:       "云信-圈组-{groupName|channelId}"
   *
   * Other platforms use the original "IM-{platform}-{timestamp}" style.
   */
    if (platform === 'nim') {
    }


    // Build media instruction for IM media sending capability


    if (imSettings.skillsEnabled && this.getSkillsPrompt) {
    }

    // Append media instruction at the end so it's always present
    if (mediaInstruction) {
    }


  private isSessionNotFoundError(error: unknown): boolean {
  }

  private isRecoverableApi400Error(error: unknown): boolean {
  }

  private shouldRetryWithFreshSession(error: unknown, message: IMMessage): boolean {
  }

  /**
   * Handle message event from CoworkRunner
   */
  private handleMessage(sessionId: string, message: CoworkMessage): void {
  }

  /**
   * Handle message update event (streaming content)
   */
  private handleMessageUpdate(sessionId: string, messageId: string, content: string): void {
  }

  private createConversationKey(conversationId: string, platform: IMPlatform): string {
  }

  private createAccumulatorPromise(sessionId: string): Promise<string> {
  }

  private rejectAccumulator(sessionId: string, error: Error): void {
  }

  private clearPendingPermissionByKey(key: string): PendingIMPermission | null {
  }

  private clearPendingPermissionsBySessionId(sessionId: string): void {
  }

  private buildIMPermissionPrompt(request: PermissionRequest): string {
  }

  private buildAllowPermissionResult(request: PermissionRequest): PermissionResult {
  }


    if (!normalizedReply) {
    }





  /**
   * Handle permission request in IM mode with explicit user confirmation.
   */
  private handlePermissionRequest(sessionId: string, request: PermissionRequest): void {
  }

  /**
   * Handle session complete event
   */
  private handleComplete(sessionId: string): void {
  }

  /**
   * Handle session error event
   */
  private handleError(sessionId: string, error: string): void {
  }

  /**
   * Clean up accumulator
   */
  private cleanupAccumulator(sessionId: string): void {
  }

  /**
   * Format accumulated messages into a reply string
   */
  private formatReply(messages: CoworkMessage[]): string {
  }

  /**
   * Format message content with media attachment information
   * Appends media metadata to content so AI can access the files
   */
  private formatMessageWithMedia(message: IMMessage): string {
  }

  /**
   * Cleanup when handler is destroyed
   */
  destroy(): void {
  }
