import { ALLOWED_LOG_LEVELS, type LogLevel, tryParseLogLevel } from "./levels.js";
import { loggingState } from "./state.js";
export function resolveEnvLogLevelOverride(): LogLevel | undefined;
