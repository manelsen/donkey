import util from "node:util";
import type { OpenClawConfig } from "../config/types.js";
import { isVerbose } from "../globals.js";
import { stripAnsi } from "../terminal/ansi.js";
import { readLoggingConfig } from "./config.js";
import { resolveEnvLogLevelOverride } from "./env-log-level.js";
import { type LogLevel, normalizeLogLevel } from "./levels.js";
import { getLogger, type LoggerSettings } from "./logger.js";
import { resolveNodeRequireFromMeta } from "./node-require.js";
import { loggingState } from "./state.js";
import { formatLocalIsoWithOffset } from "./timestamps.js";
export type ConsoleStyle = "pretty" | "compact" | "json";
type ConsoleSettings = {
export type ConsoleLoggerSettings = ConsoleSettings;
type ConsoleConfigLoader = () => OpenClawConfig["logging"] | undefined;
export function setConsoleConfigLoaderForTests(loader?: ConsoleConfigLoader): void;
function normalizeConsoleLevel(level?: string): LogLevel;
function normalizeConsoleStyle(style?: string): ConsoleStyle;
function resolveConsoleSettings(): ConsoleSettings;
function consoleSettingsChanged(a: ConsoleSettings | null, b: ConsoleSettings);
export function getConsoleSettings(): ConsoleLoggerSettings;
export function getResolvedConsoleSettings(): ConsoleLoggerSettings;
export function routeLogsToStderr(): void;
export function setConsoleSubsystemFilter(filters?: string[] | null): void;
export function setConsoleTimestampPrefix(enabled: boolean): void;
export function shouldLogSubsystemToConsole(subsystem: string): boolean;
function shouldSuppressConsoleMessage(message: string): boolean;
function isEpipeError(err: unknown): boolean;
export function formatConsoleTimestamp(style: ConsoleStyle): string;
function hasTimestampPrefix(value: string): boolean;
function isJsonPayload(value: string): boolean;
/**
 * Route console.* calls through file logging while still emitting to stdout/stderr.
 * This keeps user-facing output unchanged but guarantees every console call is captured in log files.
 */
export function enableConsoleCapture(): void;
