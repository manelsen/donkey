import { store } from '../store';
import {
import type {

class CoworkService {

  async init(): Promise<void> {
  }

  private setupStreamListeners(): void {
  }

  private cleanupListeners(): void {
  }

  async loadSessions(): Promise<void> {
  }

  async loadConfig(): Promise<void> {
  }

  async startSession(options: CoworkStartOptions): Promise<CoworkSession | null> {
  }

  async continueSession(options: CoworkContinueOptions): Promise<boolean> {
  }

  async stopSession(sessionId: string): Promise<boolean> {
  }

  async deleteSession(sessionId: string): Promise<boolean> {
  }

  async deleteSessions(sessionIds: string[]): Promise<boolean> {
  }

  async setSessionPinned(sessionId: string, pinned: boolean): Promise<boolean> {
  }

  async renameSession(sessionId: string, title: string): Promise<boolean> {
  }

    if (!cowork?.exportResultImage) {
    }


    if (!cowork?.captureImageChunk) {
    }


    if (!cowork?.saveResultImage) {
    }


  async loadSession(sessionId: string): Promise<CoworkSession | null> {
  }

  async respondToPermission(requestId: string, result: CoworkPermissionResult): Promise<boolean> {
  }

  async updateConfig(config: CoworkConfigUpdate): Promise<boolean> {
  }

  async getApiConfig(): Promise<CoworkApiConfig | null> {
  }

  async checkApiConfig(options?: { probeModel?: boolean }): Promise<{ hasConfig: boolean; config: CoworkApiConfig | null; error?: string } | null> {
  }

  async saveApiConfig(config: CoworkApiConfig): Promise<{ success: boolean; error?: string } | null> {
  }

  async getSandboxStatus(): Promise<CoworkSandboxStatus | null> {
  }

  async installSandbox(): Promise<{ success: boolean; status: CoworkSandboxStatus; error?: string } | null> {
  }




  async deleteMemoryEntry(input: { id: string }): Promise<boolean> {
  }

  async getMemoryStats(): Promise<CoworkMemoryStats | null> {
  }

    if (!window.electron?.cowork?.onSandboxDownloadProgress) {
    }

  async generateSessionTitle(prompt: string | null): Promise<string | null> {
  }

  async getRecentCwds(limit?: number): Promise<string[]> {
  }

  clearSession(): void {
  }

  destroy(): void {
  }

export const coworkService = new CoworkService();
