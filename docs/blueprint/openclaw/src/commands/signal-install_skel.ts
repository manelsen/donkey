import { createWriteStream } from "node:fs";
import fs from "node:fs/promises";
import { request } from "node:https";
import os from "node:os";
import path from "node:path";
import { pipeline } from "node:stream/promises";
import { extractArchive } from "../infra/archive.js";
import { resolveBrewExecutable } from "../infra/brew.js";
import { runCommandWithTimeout } from "../process/exec.js";
import type { RuntimeEnv } from "../runtime.js";
import { CONFIG_DIR } from "../utils.js";
export type ReleaseAsset = {
export type NamedAsset = {
type ReleaseResponse = {
export type SignalInstallResult = {
/** @internal Exported for testing. */
export async function extractSignalCliArchive(;
/** @internal Exported for testing. */
export function looksLikeArchive(name: string): boolean;
/**
 * Pick a native release asset from the official GitHub releases.
 *
 * The official signal-cli releases only publish native (GraalVM) binaries for
 * x86-64 Linux.  On architectures where no native asset is available this
 * returns `undefined` so the caller can fall back to a different install
 * strategy (e.g. Homebrew).
 */
/** @internal Exported for testing. */
export function pickAsset(;
async function downloadToFile(url: string, dest: string, maxRedirects = 5): Promise<void>;
async function findSignalCliBinary(root: string): Promise<string | null>;
async function resolveBrewSignalCliPath(brewExe: string): Promise<string | null>;
async function installSignalCliViaBrew(runtime: RuntimeEnv): Promise<SignalInstallResult>;
async function installSignalCliFromRelease(runtime: RuntimeEnv): Promise<SignalInstallResult>;
export async function installSignalCli(runtime: RuntimeEnv): Promise<SignalInstallResult>;
