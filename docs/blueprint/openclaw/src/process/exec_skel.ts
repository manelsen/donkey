import { execFile, spawn } from "node:child_process";
import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { promisify } from "node:util";
import { danger, shouldLogVerbose } from "../globals.js";
import { markOpenClawExecEnv } from "../infra/openclaw-exec-env.js";
import { logDebug, logError } from "../logger.js";
import { resolveCommandStdio } from "./spawn-utils.js";
import { resolveWindowsCommandShim } from "./windows-command.js";
function isWindowsBatchCommand(resolvedCommand: string): boolean;
function escapeForCmdExe(arg: string): string;
function buildCmdExeCommandLine(resolvedCommand: string, args: string[]): string;
/**
 * On Windows, Node 18.20.2+ (CVE-2024-27980) rejects spawning .cmd/.bat directly
 * without shell, causing EINVAL. Resolve npm/npx to node + cli script so we
 * spawn node.exe instead of npm.cmd.
 */
function resolveNpmArgvForWindows(argv: string[]): string[] | null;
/**
 * Resolves a command for Windows compatibility.
 * On Windows, non-.exe commands (like pnpm, yarn) are resolved to .cmd; npm/npx
 * are handled by resolveNpmArgvForWindows to avoid spawn EINVAL (no direct .cmd).
 */
function resolveCommand(command: string): string;
export function shouldSpawnWithShell(params:;
export async function runExec(;
export type SpawnResult = {
export type CommandOptions = {
export function resolveCommandEnv(params:;
export async function runCommandWithTimeout(;
