export const ALLOWED_LOG_LEVELS = [
export type LogLevel = (typeof ALLOWED_LOG_LEVELS)[number];
export function tryParseLogLevel(level?: string): LogLevel | undefined;
export function normalizeLogLevel(level?: string, fallback: LogLevel = "info");
export function levelToMinLevel(level: LogLevel): number;
