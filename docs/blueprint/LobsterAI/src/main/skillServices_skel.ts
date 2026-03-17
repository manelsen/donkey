/**
 * Skill Services Manager - Manages background services for skills
 */

import { execSync, spawn, spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import { app } from 'electron';
import { cpRecursiveSync } from './fsCompat';
import { getElectronNodeRuntimePath } from './libs/coworkUtil';
import { appendPythonRuntimeToEnv } from './libs/pythonRuntime';

/**
 * Resolve the user's login shell PATH on macOS/Linux.
 * Packaged Electron apps on macOS don't inherit the user's shell profile,
 * so node/npm won't be in PATH unless we resolve it explicitly.
 */
function resolveUserShellPath(): string | null {
}

/**
 * Build an environment for spawning skill service scripts.
 * Merges the user's shell PATH with the current process environment.
 */
function buildSkillServiceEnv(): Record<string, string | undefined> {
}

export class SkillServiceManager {

  private hasWebSearchRuntimeScriptSupport(skillPath: string): boolean {
  }

  private hasLegacyWebSearchEncodingHeuristic(serverEntry: string): boolean {
  }

  private isWebSearchDistOutdated(skillPath: string): boolean {
  }

  private isWebSearchRuntimeHealthy(skillPath: string): boolean {
  }

  private hasCommand(command: string, env: NodeJS.ProcessEnv): boolean {
  }

  private repairWebSearchRuntimeFromBundled(skillPath: string): void {
  }



  private ensureWebSearchRuntimeReady(skillPath: string): void {
  }

  /**
   * Start all skill services
   */
  async startAll(): Promise<void> {
  }

  /**
   * Stop all skill services
   */
  async stopAll(): Promise<void> {
  }

  /**
   * Start Web Search Bridge Server
   */
  async startWebSearchService(): Promise<void> {
  }


    // Node/Electron validates stdio streams synchronously. Use fd to avoid
    // races where createWriteStream has not opened the file descriptor yet.



  /**
   * Stop Web Search Bridge Server
   */
  async stopWebSearchService(): Promise<void> {
  }

  /**
   * Check if Web Search service is running
   */
  isWebSearchServiceRunning(): boolean {
  }

  /**
   * Get Web Search skill path
   */
  private getWebSearchPath(): string | null {
  }

  /**
   * Get service status
   */
  getStatus(): { webSearch: boolean } {
  }

  /**
   * Health check for Web Search service
   */
  async checkWebSearchHealth(): Promise<boolean> {
  }

// Singleton instance
let serviceManager: SkillServiceManager | null;

export function getSkillServiceManager(): SkillServiceManager {
  if (!serviceManager) {
  }
