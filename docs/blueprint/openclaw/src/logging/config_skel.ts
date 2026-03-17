import fs from "node:fs";
import json5 from "json5";
import { resolveConfigPath } from "../config/paths.js";
import type { OpenClawConfig } from "../config/types.js";
type LoggingConfig = OpenClawConfig["logging"];
export function readLoggingConfig(): LoggingConfig | undefined;
