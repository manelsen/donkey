import { clearActiveProgressLine } from "./terminal/progress-line.js";
import { restoreTerminalState } from "./terminal/restore.js";
export type RuntimeEnv = {
function shouldEmitRuntimeLog(env: NodeJS.ProcessEnv = process.env): boolean;
function createRuntimeIo(): Pick<RuntimeEnv, "log" | "error">;
export const defaultRuntime: RuntimeEnv = {
export function createNonExitingRuntime(): RuntimeEnv;
