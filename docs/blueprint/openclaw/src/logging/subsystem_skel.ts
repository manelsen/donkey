import { Chalk } from "chalk";
import type { Logger as TsLogger } from "tslog";
import { isVerbose } from "../globals.js";
import { defaultRuntime, type RuntimeEnv } from "../runtime.js";
import { clearActiveProgressLine } from "../terminal/progress-line.js";
import {
import { type LogLevel, levelToMinLevel } from "./levels.js";
import { getChildLogger, isFileLogLevelEnabled } from "./logger.js";
import { loggingState } from "./state.js";
type LogObj = { date?: Date } & Record<string, unknown>;
export type SubsystemLogger = {
function shouldLogToConsole(level: LogLevel, settings:;
type ChalkInstance = InstanceType<typeof Chalk>;
function formatRuntimeArg(arg: unknown): string;
function isRichConsoleEnv(): boolean;
function getColorForConsole(): ChalkInstance;
function pickSubsystemColor(color: ChalkInstance, subsystem: string): ChalkInstance;
function formatSubsystemForConsole(subsystem: string): string;
export function stripRedundantSubsystemPrefixForConsole(;
function formatConsoleLine(opts:;
function writeConsoleLine(level: LogLevel, line: string);
function shouldSuppressProbeConsoleLine(params:;
function logToFile(;
export function createSubsystemLogger(subsystem: string): SubsystemLogger;
export function runtimeForLogger(;
export function createSubsystemRuntime(;
