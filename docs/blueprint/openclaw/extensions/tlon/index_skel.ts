import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/tlon";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/tlon";
import { tlonPlugin } from "./src/channel.js";
import { setTlonRuntime } from "./src/runtime.js";
/**
 * Find the tlon binary from the skill package
 */
function findTlonBinary(): string;
/**
 * Shell-like argument splitter that respects quotes
 */
function shellSplit(str: string): string[];
/**
 * Run the tlon command and return the result
 */
function runTlonCommand(binary: string, args: string[]): Promise<string>;
export default plugin;
