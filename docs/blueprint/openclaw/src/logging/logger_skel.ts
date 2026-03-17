import fs from "node:fs";
import path from "node:path";
import { Logger as TsLogger } from "tslog";
import { getCommandPathWithRootOptions } from "../cli/argv.js";
import type { OpenClawConfig } from "../config/types.js";
import { resolvePreferredOpenClawTmpDir } from "../infra/tmp-openclaw-dir.js";
import { readLoggingConfig } from "./config.js";
import type { ConsoleStyle } from "./console.js";
import { resolveEnvLogLevelOverride } from "./env-log-level.js";
import { type LogLevel, levelToMinLevel, normalizeLogLevel } from "./levels.js";
import { resolveNodeRequireFromMeta } from "./node-require.js";
import { loggingState } from "./state.js";
import { formatLocalIsoWithOffset } from "./timestamps.js";
export const DEFAULT_LOG_DIR = resolvePreferredOpenClawTmpDir();
export const DEFAULT_LOG_FILE = path.join(DEFAULT_LOG_DIR, "openclaw.log"); // legacy single-file path
export type LoggerSettings = {
type LogObj = { date?: Date } & Record<string, unknown>;
type ResolvedSettings = {
export type LoggerResolvedSettings = ResolvedSettings;
export type LogTransportRecord = Record<string, unknown>;
export type LogTransport = (logObj: LogTransportRecord) => void;
function shouldSkipLoadConfigFallback(argv: string[] = process.argv): boolean;
function attachExternalTransport(logger: TsLogger<LogObj>, transport: LogTransport): void;
function canUseSilentVitestFileLogFastPath(envLevel: LogLevel | undefined): boolean;
function resolveSettings(): ResolvedSettings;
function settingsChanged(a: ResolvedSettings | null, b: ResolvedSettings);
export function isFileLogLevelEnabled(level: LogLevel): boolean;
function buildLogger(settings: ResolvedSettings): TsLogger<LogObj>;
function resolveMaxLogFileBytes(raw: unknown): number;
function getCurrentLogFileBytes(file: string): number;
function appendLogLine(file: string, line: string): boolean;
export function getLogger(): TsLogger<LogObj>;
export function getChildLogger(;
export function toPinoLikeLogger(logger: TsLogger<LogObj>, level: LogLevel): PinoLikeLogger;
export type PinoLikeLogger = {
export function getResolvedLoggerSettings(): LoggerResolvedSettings;
export function setLoggerOverride(settings: LoggerSettings | null);
export function resetLogger();
export function registerLogTransport(transport: LogTransport): () => void;
export const __test__ = {
function formatLocalDate(date: Date): string;
function defaultRollingPathForToday(): string;
function isRollingPath(file: string): boolean;
function pruneOldRollingLogs(dir: string): void;
