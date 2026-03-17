import path from "node:path";
import { formatCliCommand } from "../cli/command-format.js";
import type { OpenClawConfig } from "../config/config.js";
import { note } from "../terminal/note.js";
type PreflightFailureKind = "tls-cert" | "network";
export type OpenAIOAuthTlsPreflightResult =
function asRecord(value: unknown): Record<string, unknown> | null;
function extractFailure(error: unknown):;
function resolveHomebrewPrefixFromExecPath(execPath: string): string | null;
function resolveCertBundlePath(): string | null;
function hasOpenAICodexOAuthProfile(cfg: OpenClawConfig): boolean;
function shouldRunOpenAIOAuthTlsPrerequisites(params:;
export async function runOpenAIOAuthTlsPreflight(options?:;
export function formatOpenAIOAuthTlsPreflightFix(;
export async function noteOpenAIOAuthTlsPrerequisites(params:;
