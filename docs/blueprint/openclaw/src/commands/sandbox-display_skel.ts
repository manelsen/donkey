/**
 * Display utilities for sandbox CLI
 */
import type { SandboxBrowserInfo, SandboxContainerInfo } from "../agents/sandbox.js";
import { formatCliCommand } from "../cli/command-format.js";
import { formatDurationCompact } from "../infra/format-time/format-duration.ts";
import type { RuntimeEnv } from "../runtime.js";
import { formatImageMatch, formatSimpleStatus, formatStatus } from "./sandbox-formatters.js";
type DisplayConfig<T> = {
function displayItems<T>(items: T[], config: DisplayConfig<T>, runtime: RuntimeEnv): void;
export function displayContainers(containers: SandboxContainerInfo[], runtime: RuntimeEnv): void;
export function displayBrowsers(browsers: SandboxBrowserInfo[], runtime: RuntimeEnv): void;
export function displaySummary(;
export function displayRecreatePreview(;
export function displayRecreateResult(;
