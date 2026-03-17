/**
 * NIM QChat Client
 * Manages QChat (Circle Groups / 圈组) subscriptions for receiving and sending messages
 * Adapted from openclaw-nim/src/qchat-client.ts for Electron main process
 */

/**
 * QChat message payload from SDK (supports both camelCase and snake_case variants)
 */
export interface QChatMessagePayload {
  // Snake_case variants from SDK

/**
 * Parsed QChat inbound message
 */
export interface QChatInboundMessage {

/**
 * QChat client options
 */
export interface QChatClientOptions {

/**
 * NIM QChat Client
 *
 * Two-phase lifecycle:
 *   1. initListeners() — register passive event handlers (call AFTER IM init, BEFORE login)
 *   2. activate()      — discover servers & subscribe (call AFTER IM login succeeds)
 */
export class NimQChatClient {

  constructor(opts: QChatClientOptions) {
  }

  /**
   * Set the NIM SDK instance to use (reuse existing V2NIM instance)
   * Must be called before initListeners()
   */
  setNim(nim: any): void {
  }

  get account(): string {
  }

  get isListening(): boolean {
  }

  get isActivated(): boolean {
  }

  /**
   * Normalize message fields (handle both camelCase and snake_case variants)
   */
  private normalizeMessage(msg: QChatMessagePayload): QChatMessagePayload {
  }

  /**
   * Parse QChat message and detect @-mention
   */
  parseMessage(msg: QChatMessagePayload): QChatInboundMessage | null {
  }

  /**
   * Phase 1 — Register passive event handlers.
   * Call this AFTER V2NIM init but BEFORE login.
   * Only registers listeners; makes NO outgoing API calls.
   */
  async initListeners(): Promise<void> {
  }

  /**
   * Phase 2 — Discover servers and subscribe to channels.
   * Call this AFTER IM login succeeds.
   * Makes active API calls (getServersByPage, subscribeAllChannel).
   */
  async activate(): Promise<void> {
  }

  /**
   * Auto-discover joined servers by paginating through getServersByPage
   */
const serverIds: string[];

    for (let page = 0; page < 20; page++) {
    }


  /**
   * Subscribe to a single server (used for dynamic subscription)
   */



  /**
   * Send a text message to a QChat channel
   */



  /**
   * Stop and clean up QChat subscriptions
   */
  async stop(): Promise<void> {
  }
