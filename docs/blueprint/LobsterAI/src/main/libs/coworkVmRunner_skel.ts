import { app } from 'electron';
import { spawn, type ChildProcessByStdio } from 'child_process';
import fs from 'fs';
import net from 'net';
import path from 'path';
import type { Readable } from 'stream';
import { StringDecoder } from 'string_decoder';
import { v4 as uuidv4 } from 'uuid';
import type { SandboxRuntimeInfo } from './coworkSandboxRuntime';
import { coworkLog } from './coworkLogger';

export type CoworkSandboxPaths = {

export type SandboxLauncherMode = 'direct' | 'launchctl';

export type SandboxRequestInfo = {

export type SandboxCwdMapping = {

export type SandboxExtraMount = {

export function ensureCoworkSandboxDirs(sessionId: string): CoworkSandboxPaths {



export function resolveSandboxCwd(cwd: string): SandboxCwdMapping {
  // On all platforms, mount the host directory to /workspace/project inside the VM
  // This ensures a consistent Linux path inside the Alpine VM


/**
 * Collect skill files for transfer into the sandbox VM.
 * Walks the skills directory, skipping heavy/transient dirs and large files.
 * Returns an array of { path, data } entries with forward-slash relative paths.
 */
export function collectSkillFilesForSandbox(
const result: { path: string; data: Buffer }[];


  function scan(dir: string, base: string): void {
  }


export function buildSandboxRequest(

function getPreferredAccel(): string | null {
}

function resolveRuntimeRoot(runtimeBinary: string): string {
}

function toQemuOptionPath(targetPath: string): string {
}

function resolveAarch64Firmware(options: {
}

function buildQemuArgs(options: {
}

/**
 * Find a free TCP port on 127.0.0.1 by briefly binding to port 0.
 */
export function findFreePort(): Promise<number> {

export function spawnCoworkSandboxVm(options: {


  if (options.launcher === 'launchctl' && process.platform === 'darwin') {
  }

// ---------------------------------------------------------------------------
// VirtioSerialBridge — TCP bridge for Windows virtio-serial IPC
// ---------------------------------------------------------------------------
// QEMU exposes the guest's virtio-serial port as a TCP server.  The bridge
// connects as a TCP client and translates JSON-line messages:
//   Guest → Host: heartbeat, stream, response  → written to local ipcDir files
//   Host → Guest: request, permission_response  → sent over TCP
// This keeps the existing file-polling code (waitForVmReady, readSandboxStream)
// working unchanged on the host side.
// ---------------------------------------------------------------------------

export class VirtioSerialBridge {
  // Chunked transfer buffers: transferId -> { chunks, totalChunks, path }

  constructor(ipcDir: string, hostCwd?: string) {
  }

  /** Update the host CWD for file sync (e.g. on multi-turn continuation) */
  setHostCwd(hostCwd: string): void {
  }

  /**
   * Try to connect to QEMU's virtio-serial TCP server with retries.
   * QEMU may need a moment to start listening after spawn.
   */
  async connect(port: number, timeoutMs = 30000): Promise<void> {
  }

  private tryConnect(port: number): Promise<void> {
  }

  private setupReader(sock: net.Socket): void {
  }

  private handleLine(line: string): void {
  }

  // -------------------------------------------------------------------------
  // File sync handlers — guest -> host file transfer
  // -------------------------------------------------------------------------

  /**
   * Validate and resolve a guest-relative path to an absolute host path.
   * Returns null if the path is invalid or escapes the host CWD.
   */
  private resolveHostPath(relativePath: string): string | null {
  }

  private handleFileSync(msg: Record<string, unknown>): void {
  }

  private handleFileSyncChunk(msg: Record<string, unknown>): void {
  }

  private handleFileSyncComplete(msg: Record<string, unknown>): void {
  }

  private assembleAndWriteChunked(transferId: string): void {
  }

  /** Send a sandbox request to the guest via serial */
  sendRequest(requestId: string, data: Record<string, unknown>): void {
  }

  /** Send a permission response to the guest via serial */
  sendPermissionResponse(requestId: string, result: Record<string, unknown>): void {
  }

  /** Send a host tool response to the guest via serial */
  sendHostToolResponse(requestId: string, payload: Record<string, unknown>): void {
  }

  /**
   * Push a file from host to guest via serial.
   * Used to transfer skill files into the sandbox on Windows (where 9p is unavailable).
   */
  pushFile(basePath: string, relativePath: string, data: Buffer): void {
  }

  private sendLine(data: Record<string, unknown>): void {
  }

  close(): void {
  }
