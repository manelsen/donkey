import { EventEmitter } from 'events';
import { type ChildProcessByStdio, spawn, spawnSync } from 'child_process';
import { app } from 'electron';
import fs from 'fs';
import path from 'path';
import type { Readable } from 'stream';
import { StringDecoder } from 'string_decoder';
import { v4 as uuidv4 } from 'uuid';
import type { PermissionResult } from '@anthropic-ai/claude-agent-sdk';
import type { CoworkStore, CoworkMessage, CoworkExecutionMode } from '../coworkStore';
import { getClaudeCodePath, getCurrentApiConfig } from './claudeSettings';
import { loadClaudeSdk } from './claudeSdk';
import { getElectronNodeRuntimePath, getEnhancedEnv, getEnhancedEnvWithTmpdir, getSkillsRoot } from './coworkUtil';
import { coworkLog, getCoworkLogPath } from './coworkLogger';
import { ensurePythonPipReady, ensurePythonRuntimeReady } from './pythonRuntime';
import { cpRecursiveSync } from '../fsCompat';
import { isQuestionLikeMemoryText, type CoworkMemoryGuardLevel } from './coworkMemoryExtractor';
import { z } from 'zod';
import { ensureSandboxReady, getSandboxRuntimeInfoIfReady, type SandboxRuntimeInfo } from './coworkSandboxRuntime';
import {
  type SandboxCwdMapping,
  type SandboxExtraMount,


// On macOS/Linux, keep sandbox skills outside the project workspace mount to
// avoid creating SKILLs directories in the user's selected host folder.
// On Windows, keep historical path for compatibility with serial-mode flows.
const PYTHON_BASH_COMMAND_RE = /(?:^|[^\w.-])(?:python(?:3)?|py(?:\.exe)?|pip(?:3)?)(?:\s+-3)?(?:\s|$)|\.py(?:\s|$)/i;
const PYTHON_PIP_BASH_COMMAND_RE = /(?:^|[^\w.-])(?:pip(?:3)?|python(?:3)?\s+-m\s+pip|py(?:\.exe)?\s+-m\s+pip)(?:\s|$)/i;
const MEMORY_PROCEDURAL_TEXT_RE = /(执行以下命令|run\s+(?:the\s+)?following\s+command|\b(?:cd|npm|pnpm|yarn|node|python|bash|sh|git|curl|wget)\b|\$[A-Z_][A-Z0-9_]*|&&|--[a-z0-9-]+|\/tmp\/|\.sh\b|\.bat\b|\.ps1\b)/i;

function ensureWindowsChildProcessHideInitScript(): string | null {
}

function prependNodeRequireArg(args: string[], scriptPath: string): string[] {
}

function escapeRegExp(value: string): string {
}

function findSkillsMarkerIndex(value: string): number {
}

function isPathWithin(basePath: string, targetPath: string): boolean {
}

function resolveSkillPathFromRoots(



  if (markerIndex >= 0) {
  }

  if (skillId) {
  }


function detectBinaryMagic(filePath: string): string {
}

function summarizeRuntimeBinary(runtimeBinary: string): string {
}


function persistSandboxSpawnDiagnostics(


function formatSandboxSpawnError(
const details: string[];

function summarizeEndpointForLog(rawValue: string | undefined): string | null {
}

function extractHostFromUrl(rawValue: string | undefined): string | null {
}

function mergeNoProxyList(currentValue: string | undefined, requiredHosts: string[]): string {
}

// Event types emitted by the runner
export interface CoworkRunnerEvents {

export interface PermissionRequest {

interface ActiveSession {
  // Track the current streaming message for incremental updates
  // Track thinking block streaming
  // Track which block type is currently streaming (to distinguish on content_block_stop)
  /** Resolve callback for the current sandbox turn; called by the result event handler. */
  /** When true, auto-approve all tool permissions (for scheduled tasks) */

interface PendingPermission {

interface SandboxPendingPermission {

interface QueuedTurnMemoryUpdate {

type AttachmentEntry = {

type SandboxSkillRewriteOptions = {

type SandboxSkillEntry = {

type SandboxSkillRootMount = {

export class CoworkRunner extends EventEmitter {

  constructor(store: CoworkStore) {
  }


  private isSessionStopRequested(sessionId: string, activeSession?: ActiveSession): boolean {
  }

  private applyTurnMemoryUpdatesForSession(sessionId: string): void {
  }

  private getSandboxUnavailableFallbackNotice(errorMessage: string): string {
  }

    if (this.drainingTurnMemoryQueue) {
    }
      while (this.turnMemoryQueue.length > 0) {
      }
      if (this.turnMemoryQueue.length > 0) {
      }

  private escapeXml(value: string): string {
  }

  private buildUserMemoriesXml(): string {
  }

    if (records.length === 0) {
    }


    if (input.reason) {
    }
    if (input.payload) {
    }

  private sanitizeMemoryToolText(raw: string): string {
  }

  private validateMemoryToolText(rawText: string): { ok: boolean; text: string; reason?: string } {
  }



    if (args.action === 'list') {
    }

    if (args.action === 'add') {
    }

    if (args.action === 'update') {
    }



  private isDirectory(target: string): boolean {
  }

  private extractHostSkillRootsFromPrompt(systemPrompt: string): string[] {
  }

const candidates: string[];
    const pushCandidate = (candidate?: string | null) => {


    if (app.isPackaged) {
    }



const orderedSkillIds: string[];

    const upsertSkill = (skillId: string, hostPath: string) => {
        if (index >= 0) {
        }

    const collectFromSkillDir = (skillDir: string) => {
      if (!skillId) {
      }

    for (const root of hostSkillsRoots) {
    }


    if (skillEntries.length === 0) {
    }

    if (runtimePlatform === 'win32') {
    }

    const keyOf = (target: string): string => (
    for (const entry of skillEntries) {
    }

const mountHostRoots: string[];
    const pushMountRoot = (candidate: string) => {

    for (const root of hostSkillsRoots) {
    }
    for (const root of entryRoots) {
    }


    const extraMounts = rootMounts.map(({ hostRoot, mountTag }) => ({ hostPath: hostRoot, mountTag }));
    const skillMounts = rootMounts.reduce<Record<string, { tag: string; guestPath: string }>>((acc, entry, index) => {


const sandboxEnv: Record<string, string>;

    // In QEMU user-mode networking, the host is accessible at 10.0.2.2
    // Remap localhost/127.0.0.1 proxy URLs to the QEMU gateway
    const remapLocalhostToQemuGateway = (url: string): string => {

    for (const key of SANDBOX_ALLOWED_ENV_KEYS) {
    }

    if (envTimezone) {
    }

    if (guestSkillsRoot) {
    }

    // Ensure requests to host-side services bypass system HTTP proxies.


    // Some SDK/network stacks may ignore NO_PROXY for local gateway addresses.
    // When model traffic is explicitly routed to host gateway, force direct mode.
    if (shouldForceDirectHostRouting) {
    }


  private parseAttachmentEntries(prompt: string): AttachmentEntry[] {
  }

  private resolveAttachmentPath(inputPath: string, cwd: string): string {
  }

  private toWorkspaceRelativePromptPath(cwd: string, absolutePath: string): string {
  }






  /**
   * Push staged attachment files from .cowork-temp/attachments/{sessionId}/ to
   * the sandbox VM via virtio-serial bridge.  On macOS/Linux, attachments are
   * accessible via 9p mount, so this is only needed on Windows (serial mode).
   */

const files: { relativePath: string; data: Buffer }[];
    const scan = (dir: string, base: string): void => {
      for (const entry of entries) {
      }

    if (files.length === 0) {
    }

    for (const file of files) {
    }

  private preparePromptForSandbox(prompt: string, cwd: string, sessionId: string): {
  }

  private findWorkspaceFileByName(cwd: string, fileName: string, maxMatches = 2): string[] {
  }

  private resolveInferredFilePath(candidate: string, cwd: string): string | null {
  }

  private inferReferencedWorkspaceFiles(prompt: string, cwd: string): string[] {
  }

  private augmentPromptWithReferencedWorkspaceFiles(prompt: string, cwd: string): string {
  }

  private truncateSandboxHistoryContent(content: string, maxChars: number): string {
  }

  private truncateLargeContent(content: string, maxChars: number): string {
  }


    const visit = (current: unknown, depth: number): unknown => {
      if (typeof current === 'string') {
      }
      if (typeof current === 'bigint') {
      }
      if (typeof current === 'function') {
      }
      if (depth >= maxDepth) {
      }
        if (current.length > maxItems) {
        }
      if (typeof current === 'object') {
      }


    if (!delta || isTruncated) {
    }

    if (nextLength <= maxChars) {
    }

    const head = remaining > 0 ? `${current}${delta.slice(0, remaining)}` : current;

    if (force || now - lastEmitAt >= STREAM_UPDATE_THROTTLE_MS) {
    }

  private formatSandboxHistoryMessage(message: CoworkMessage): string | null {
  }

    if (messages.length === 0) {
    }


const selectedFromNewest: string[];
    for (let i = history.length - 1; i >= 0; i -= 1) {
    }


  private buildSandboxHistoryBlocks(messages: CoworkMessage[], currentPrompt: string): string[] {
  }

  private injectSandboxHistoryPrompt(sessionId: string, currentPrompt: string, effectivePrompt: string): string {
  }

  /**
   * Inject conversation history into a local-mode prompt when the session is
   * restarted after a stop (subprocess was killed, no SDK session to resume).
   */
  private injectLocalHistoryPrompt(sessionId: string, currentPrompt: string, effectivePrompt: string): string {
  }

    if (!guestSkillsRoot) {
    }

    for (const mapping of mappings) {
    }

    for (const variant of skillRootVariants) {
    }

    for (const legacyRoot of LEGACY_SKILLS_ROOT_HINTS) {
    }


    if (!guestSkillsRoot) {
    }

    if (!rawLocation) {
    }

    for (const mapping of options.hostSkillsRootMounts ?? []) {
    }
    for (const guestRoot of guestRoots) {
    }

    if (mappedHostLocation) {
    }

    if (markerIndex >= 0) {
    }

    for (const legacyRoot of LEGACY_SKILLS_ROOT_HINTS) {
    }


    if (!systemPrompt) {
    }

    if (!guestSkillsRoot) {
    }

        if (openTag !== closeTag) {
        }
        if (!mapped) {
        }

      for (const variant of variants) {
      }
      if (next !== rewritten) {
      }

    for (const legacyRoot of LEGACY_SKILLS_ROOT_HINTS) {
    }


const mappings: Array<{ hostRoot: string; guestRoot: string }>;
    const keyOf = (target: string): string => (

    const pushMapping = (hostRoot: string, guestRoot: string) => {

    for (const mount of options.hostSkillsRootMounts ?? []) {
    }

    if (mappings.length === 0) {
    }



    for (const mapping of mappings) {
    }

  private normalizeWorkspaceRoot(workspaceRoot: string, cwd: string): string {
  }

  private inferWorkspaceRootFromSessionCwd(cwd: string): string {
  }

  private resolveHostWorkspaceFallback(workspaceRoot: string): string | null {
  }

  private mapSandboxGuestCwdToHost(cwd: string, hostWorkspaceRoot: string): string | null {
  }

  private resolveSessionCwdForExecution(sessionId: string, cwd: string, workspaceRoot: string): string {
  }

  private formatLocalDateTime(date: Date): string {
  }

  private formatLocalIsoWithoutTimezone(date: Date): string {
  }

  private formatUtcOffset(date: Date): string {
  }

  private buildLocalTimeContextPrompt(): string {
  }

  private buildWindowsEncodingPrompt(): string {
  }

  private buildWindowsBundledRuntimePrompt(): string {
  }



    if (memoryEnabled) {
    }

  /**
   * Build a dynamic prompt prefix containing time context and user memories.
   * These are prepended to the user message (not the system prompt) so that
   * the system prompt stays stable across turns and can benefit from prompt caching.
   */
  private buildPromptPrefix(): string {
  }

  private extractToolCommand(toolInput: Record<string, unknown>): string {
  }

  private isDeleteOperation(toolName: string, toolInput: Record<string, unknown>): boolean {
  }

  private truncateCommandPreview(command: string, maxLength = 120): string {
  }


  private isSafetyApproval(result: PermissionResult, question: string): boolean {
  }

const request: PermissionRequest;


    if (activeSession.abortController.signal.aborted || signal.aborted) {
    }

      if (!approved) {
      }


  private isPythonRelatedBashCommand(command: string): boolean {
  }

  private isPythonPipBashCommand(command: string): boolean {
  }


    if (runtimeResult.success) {
    }


    if (!session) {
    }

    // Mark session as running

    if (!options.skipInitialUserMessage) {
    }

    // Create abort controller

    // Store active session
const activeSession: ActiveSession;
    if (session.cwd !== sessionCwd) {
    }


    // Run claude-code using the SDK
      let effectivePrompt = promptPrefix ? `${promptPrefix}\n\n---\n\n${prompt}` : prompt;

      // If the session already has messages (restarted after stop), inject
      // conversation history so the model retains context from prior turns.
      if (currentSession && currentSession.messages.length > 0) {
      }


  async continueSession(sessionId: string, prompt: string, options: { systemPrompt?: string; skillIds?: string[]; imageAttachments?: Array<{ name: string; mimeType: string; base64Data: string }> } = {}): Promise<void> {
  }

  stopSession(sessionId: string): void {
  }

  respondToPermission(requestId: string, result: PermissionResult): void {
  }

  private handleHostToolExecution(payload: Record<string, unknown>): { success: boolean; text: string } {
  }

    if (activeSession.ipcBridge) {
    }

    if (activeSession.ipcBridge) {
    }



    // Reset per-turn output dedupe flags.

    if (!apiConfig) {
    }


    // Log MCP-relevant environment for debugging
    // Log full PATH split by delimiter
    for (let i = 0; i < pathEntries.length; i++) {
    }

    // When packaged, process.execPath is the Electron binary.
    // child_process.fork() uses process.execPath by default, so without
    // ELECTRON_RUN_AS_NODE the SDK would launch another Electron app instance
    // instead of running cli.js as a Node script, causing exit code 1.
    if (app.isPackaged) {
    }

    // On Windows, check that git-bash is available before attempting to start.
    // Claude Code CLI requires git-bash for shell tool execution.
    if (process.platform === 'win32' && !envVars.CLAUDE_CODE_GIT_BASH_PATH) {
    }

    if (process.platform === 'win32') {
    }

    const handleSdkStderr = (message: string): void => {
      if (stderrTail.length > STDERR_TAIL_MAX_CHARS) {
      }

      // Detect fatal errors early and abort the session
      for (const pattern of STDERR_FATAL_PATTERNS) {
      }

const options: Record<string, unknown>;
        if (abortController.signal.aborted || signal.aborted) {
        }


        if (resolvedName === 'Bash') {
        }

        // Auto-approve mode (kept for compatibility with legacy callers).
        if (activeSession.autoApprove) {
        }

        if (resolvedName !== 'AskUserQuestion') {
        }

        if (resolvedName !== 'AskUserQuestion') {
        }

const request: PermissionRequest;


        if (abortController.signal.aborted || signal.aborted) {
        }

        if (result.behavior === 'deny') {
        }

        if (!hasAnswers) {
        }


    if (app.isPackaged) {
    }

    // The SDK session state is bound to the subprocess and its project directory.
    // After stop, the subprocess is killed and the session cannot be reliably
    // resumed (cwd/model mismatch causes "No conversation found" errors).
    // Instead, we inject conversation history into the prompt in startSession().

    if (systemPrompt) {
    }

let startupTimer: ReturnType<typeof setTimeout> | null;



const memoryTools: any[];
      if (config.memoryEnabled) {
      }

      // Inject user-configured MCP servers (local mode only)
      if (this.mcpServerProvider) {
      }

      // Log final MCP server config summary
      if (options.mcpServers) {
      }

      // Build prompt: if we have image attachments, use SDKUserMessage with content blocks
      // instead of a plain string prompt, so the model can see the images.
      if (imageAttachments && imageAttachments.length > 0) {
      }

      // Set up a startup timeout BEFORE calling query(): if no events arrive
      // within the timeout, abort. This covers both the query() call itself
      // (which spawns the subprocess) and the initial event wait.
        if (!abortController.signal.aborted) {
        }

      const result = await query({ prompt: queryPrompt, options } as any);

        // Clear startup timeout on first event
        if (startupTimer) {
        }
        const eventType = eventPayload && typeof eventPayload === 'object' ? String(eventPayload.type ?? '') : typeof event;
      // Clean up timer if loop ended before first event (e.g. empty iterator)
      if (startupTimer) {
      }


      // Ensure any remaining streaming content is saved to database

      if (session?.status !== 'error') {
      }
      // Clean up startup timer if still pending
      if (startupTimer) {
      }




const executionMode: CoworkExecutionMode;


let unresolvedSandboxAttachments: string[];
    if (shouldPrepareSandboxPrompt) {
    }

      if (executionMode === 'sandbox' || hasActiveSandboxVm) {
      }


    // If there's already a running sandbox VM with IPC bridge, send a
    // continuation request to the same VM instead of spawning a new one.
    if (hasActiveSandboxVm) {
    }

    if (executionMode === 'local') {
    }

    if (!sandboxReady.ok) {
    }

      // If the sandbox VM is still alive, keep the activeSession for multi-turn continuation.
      // Otherwise (VM exited), clean up.
      if (!activeSession.sandboxProcess || activeSession.sandboxProcess.killed) {
      }
      if (executionMode === 'sandbox') {
      }




    if (!apiConfig) {
    }


const mounts: Record<string, { tag: string; guestPath: string }>;

const input: Record<string, unknown>;

    if (imageAttachments && imageAttachments.length > 0) {
    }

    // NOTE: Do NOT pass activeSession.claudeSessionId here.  This method always
    // starts a fresh VM, so any previous SDK session ID (e.g. from a prior app
    // run stored in the DB) is unreachable by the new VM process.  Continuation
    // within the same running VM is handled by continueSandboxTurn() instead.
    // Clear the stale value so the new SDK session's ID will replace it.

    if (resolvedSystemPrompt) {
    }


    const isHvfDenied = (message: string) => message.includes('HV_DENIED');
    const isWhpxFailed = (message: string) =>
    const isMemoryAllocationFailed = (message: string) =>

      const accelMode = accelOverride ?? (process.platform === 'darwin' ? 'hvf' : process.platform === 'win32' ? 'whpx' : 'default');

      // Remove stale serial.log from previous attempt to avoid Windows file-lock conflicts
        // File may not exist (first attempt) or still locked (process not yet exited)
        const code = e && typeof e === 'object' && 'code' in e ? (e as { code: string }).code : '';
        if (code && code !== 'ENOENT') {
        }

      // On Windows, allocate a TCP port for virtio-serial IPC bridge
      if (runtimeInfo.platform === 'win32') {
      }



          // ignore kill race



      const handleLine = (line: string) => {

let payload: Record<string, unknown> | null;

        if (messageType === 'sdk_event' && payload.event) {
        }

        if (messageType === 'host_tool_request') {
        }

        if (messageType === 'permission_request') {
        }

        if (stderrBuffer.length > 10000) {
        }
        // Log QEMU stderr in real-time for diagnostics
      // Drain stdout to avoid backpressure blocking the VM process.

let streamPromise: Promise<void> | null;

        // On Windows, connect the virtio-serial bridge BEFORE waiting for VM ready,
        // because the bridge receives heartbeat messages and writes them to the local
        // file that waitForVmReady polls.
        if (ipcPort && runtimeInfo.platform === 'win32') {
        }

        // Wait for the VM to be ready before sending requests.
        // Windows TCG can be significantly slower than hardware acceleration.


        if (!vmReady) {
        }


        // On Windows (serial mode), push skill files into the sandbox
        // since 9p filesystem sharing is not available.
        if (activeSession.ipcBridge && sandboxSkills.guestSkillsRoot && sandboxSkills.skillEntries.length > 0) {
        }

        // On Windows (serial mode), push staged attachment files into the sandbox
        if (activeSession.ipcBridge) {
        }


        // On Windows, send the request via virtio-serial bridge instead of file
        if (activeSession.ipcBridge) {
        }

          // Allow the result event handler to resolve this turn without killing the VM



            // If already resolved by result event, just clean up — don't resolve again
            if (!activeSession.sandboxTurnResolve) {
            }



            if (code !== 0) {
            }

            // Only update status if not already completed (may have been set by result event)
            if (session?.status !== 'error' && session?.status !== 'completed') {
            }
        if (streamPromise) {
        }

        // If the VM is still alive (turn completed via result event), keep it
        // running for potential multi-turn continuation.
        if (vmStillAlive) {
        }



    for (let attempt = 0; attempt < 5; attempt += 1) {
    }


  /**
   * Send a continuation request to an already-running sandbox VM.
   * Reuses the existing QEMU process and IPC bridge.
   */


    // Reset per-turn output dedupe flags

    if (!apiConfig) {
    }


    // Ensure the bridge has the latest host CWD for file sync
    if (activeSession.ipcBridge) {
    }

const mounts: Record<string, { tag: string; guestPath: string }>;

const input: Record<string, unknown>;

    if (imageAttachments && imageAttachments.length > 0) {
    }

    if (activeSession.claudeSessionId) {
    }

    if (resolvedSystemPrompt) {
    }

    // On Windows (serial mode), push staged attachment files into the sandbox
    if (activeSession.ipcBridge) {
    }


    const handleLine = (line: string) => {

let payload: Record<string, unknown> | null;

      if (messageType === 'sdk_event' && payload.event) {
      }

      if (messageType === 'host_tool_request') {
      }

      if (messageType === 'permission_request') {
      }



    // Send continuation request via IPC bridge

        // Allow the result event handler to resolve this turn
          if (result.status === 'ok') {
          }

        // Handle unexpected process exit during this turn
        const onClose = (code: number | null) => {
          if (activeSession.ipcBridge) {
          }



          if (code !== 0) {
          }


      if (streamPromise) {
      }



    // Prefer keeping the original auto-routing flow (select one skill by description,
    // then read it) and only rewrite skill locations to sandbox paths.
    if (guestSkillsRoot) {
    }

    // Fallback: inline skill contents when location-based routing cannot be used.
    // Extract all <location> paths from the available_skills block
const skillContents: string[];

          // Extract skill name from the <name> tag near this location
          if (sandboxSkillDir) {
          }

    if (skillContents.length === 0) {
    }


    // Replace the auto-routing section with full skill content

    // Remap localhost/127.0.0.1 references to QEMU host gateway (10.0.2.2)
    // so that skills referencing host services work from inside the sandbox




  private resolveAssistantEventError(payload: Record<string, unknown>): string | null {
  }

  private normalizeSdkError(value: unknown): string | null {
  }

  private handleClaudeEvent(sessionId: string, event: unknown): void {
  }

    // SDKPartialAssistantMessage structure:
    // { type: 'stream_event', event: BetaRawMessageStreamEvent, ... }


    // Handle content_block_start - create a new streaming message
    if (eventType === 'content_block_start') {
    }

    // Handle content_block_delta - update the streaming message
    if (eventType === 'content_block_delta') {
    }

    // Handle content_block_stop - finalize the streaming message
    if (eventType === 'content_block_stop') {
    }

    // Handle message_stop - ensure everything is finalized
    if (eventType === 'message_stop') {
    }

  private finalizeStreamingContent(activeSession: ActiveSession): void {
  }

let timeoutId: ReturnType<typeof setTimeout> | null;

      const finalize = (result: PermissionResult) => {
        if (timeoutId) {
        }
        if (signal) {
        }



      if (signal) {
      }

  private clearPendingPermissions(sessionId: string): void {
  }

  private clearSandboxPermissions(sessionId: string): void {
  }


    // Use shorter polling interval for faster response


    // Detect early VM exit so we fail fast instead of waiting the full timeout
let processExitCode: number | null;

    while (true) {
    }

    // Log final heartbeat state for diagnostics


    const sleep = (ms: number) => new Promise(resolve => setTimeout(resolve, ms));
let fileHandle: fs.promises.FileHandle | null;

      while (!signal.aborted) {
      }
      if (fileHandle) {
      }

  private addSystemMessage(sessionId: string, content: string): void {
  }

  private findAttachmentsOutsideCwd(prompt: string, cwd: string): string[] {
  }

  private getMessageById(sessionId: string, messageId: string): CoworkMessage | undefined {
  }




    // If we have an active streaming message, prefer updating it with the final result.
    // This avoids duplicate assistant messages when result arrives before streaming completes.
    if (activeSession.currentStreamingMessageId) {
    }

    // Check if we already have assistant output with the same content
    // This catches the case where streaming is complete but hasAssistantTextOutput is set
    if (activeSession.hasAssistantTextOutput) {
    }


    // If the last assistant message is a streaming placeholder (empty or still marked streaming),
    // update it with the final result instead of adding a new message.

    if (lastAssistant && lastAssistantText === trimmed) {
    }


  private extractText(value: unknown): string | null {
  }

  private formatToolResultContent(record: Record<string, unknown>): string {
  }

  private handleError(sessionId: string, error: string): void {
  }

  isSessionActive(sessionId: string): boolean {
  }

  getSessionConfirmationMode(sessionId: string): 'modal' | 'text' | null {
  }

  getActiveSessionIds(): string[] {
  }

  stopAllSessions(): void {
  }
