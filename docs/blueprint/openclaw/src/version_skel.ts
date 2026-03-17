import { createRequire } from "node:module";
function readVersionFromJsonCandidates(;
function firstNonEmpty(...values: Array<string | undefined>): string | undefined;
export function readVersionFromPackageJsonForModuleUrl(moduleUrl: string): string | null;
export function readVersionFromBuildInfoForModuleUrl(moduleUrl: string): string | null;
export function resolveVersionFromModuleUrl(moduleUrl: string): string | null;
export function resolveBinaryVersion(params:;
export type RuntimeVersionEnv = {
export const RUNTIME_SERVICE_VERSION_FALLBACK = "unknown";
export function resolveUsableRuntimeVersion(version: string | undefined): string | undefined;
export function resolveRuntimeServiceVersion(;
export const VERSION = resolveBinaryVersion({
