import { app, session } from 'electron';
import { createHash } from 'crypto';
import { EventEmitter } from 'events';
import fs from 'fs';
import path from 'path';
import { Readable } from 'stream';
import { pipeline } from 'stream/promises';
import { createGunzip } from 'zlib';
import { spawnSync } from 'child_process';
import { coworkLog } from './coworkLogger';

export type CoworkSandboxStatus = {

export type CoworkSandboxProgress = {

export type SandboxRuntimeInfo = {

type SandboxCheckResult = { ok: true; runtimeInfo: SandboxRuntimeInfo } | { ok: false; error: string };




// Default sandbox resources for different architectures
// Note: macOS binaries are statically linked, Windows requires full QEMU installation



// Cache the resolved system QEMU path (Windows only) so getSandboxStatus()
// can report runtimeReady=true when using a system-installed QEMU.
let _resolvedSystemQemuPath: string | null;


function emitProgress(progress: CoworkSandboxProgress): void {
}

export function onSandboxProgress(listener: (progress: CoworkSandboxProgress) => void): () => void {

function getPlatformKey(): string | null {
}

function getRuntimeBinaryName(): string {
}

function getSandboxPaths() {
}

function getRuntimeUrl(platformKey: string): string | null {
}

function getArchVariant(): 'amd64' | 'arm64' | null {
}

function getImageUrl(): string | null {
}

function getImageSha256(): string | null {
}

function getKernelUrl(): string | null {
}

function getInitrdUrl(): string | null {
}

function getKernelPathOverride(): string | null {
}

function getInitrdPathOverride(): string | null {
}

async function downloadFile(url: string, destination: string, stage: CoworkSandboxProgress['stage']): Promise<void> {
}

async function sha256File(filePath: string): Promise<string> {
}

async function verifySha256(filePath: string, expected?: string | null): Promise<void> {
}

function extractTarArchive(archivePath: string, destDir: string): void {
}

function extractArchive(archivePath: string, destDir: string): void {
}

async function extractGzipBinary(archivePath: string, targetPath: string): Promise<void> {
}

async function isTarFile(filePath: string): Promise<boolean> {
}

async function isGzipFile(filePath: string): Promise<boolean> {
}

async function isPEFile(filePath: string): Promise<boolean> {
}

/**
 * Launch an NSIS installer interactively (like double-click) and wait for it to finish.
 * Uses PowerShell Start-Process which calls ShellExecute internally, properly handling
 * UAC elevation — the user sees the standard Windows elevation prompt and installer UI.
 */
async function runNsisInstaller(installerPath: string, targetDir: string): Promise<void> {
}

function resolveRuntimeBinary(runtimeDir: string, expectedPath: string): string | null {
}

/**
 * Try to find QEMU in system PATH on Windows
 */
function findSystemQemu(): string | null {
}

/**
 * Validate that a QEMU binary can actually run (not just exist)
 */
function validateQemuBinary(binaryPath: string): { valid: boolean; error?: string } {
}

/**
 * Check whether a QEMU binary has virtfs (9p filesystem) support compiled in.
 * The sandbox relies on `-virtfs` for host–guest file sharing; without it the VM
 * cannot communicate with the host.
 *
 * On Windows, virtfs is typically not supported, so we skip this check and use
 * virtio-serial as an alternative IPC channel.
 */
function checkQemuVirtfsSupport(binaryPath: string): boolean {
}

function hasHypervisorEntitlement(output: string): boolean {
}

function ensureHypervisorEntitlement(binaryPath: string, runtimeDir: string): void {
}

async function ensureRuntime(): Promise<string> {
}

async function ensureImage(): Promise<string> {
}

async function ensureKernel(): Promise<string | null> {
}

async function ensureInitrd(): Promise<string | null> {
}

function getExistingKernelPath(): string | null {
}

function getExistingInitrdPath(): string | null {
}

function resolveAvailableRuntimeBinary(): string | null {
}

// Singleton promise for ensureSandboxReady to prevent concurrent installations.
// Two simultaneous NSIS installers writing to the same directory will deadlock.
let _ensureSandboxReadyPromise: Promise<SandboxCheckResult> | null;

export function ensureSandboxReady(): Promise<SandboxCheckResult> {
  if (_ensureSandboxReadyPromise) {
  }

async function _ensureSandboxReadyImpl(): Promise<SandboxCheckResult> {
}

export function getSandboxRuntimeInfoIfReady():
  if (!platformKey) {
  }

  if (!runtimeBinary) {
  }



export function getSandboxStatus(): CoworkSandboxStatus {
  if (!platformKey) {
  }



