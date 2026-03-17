import type { ChildProcess, SpawnOptions } from "node:child_process";
import { spawn } from "node:child_process";
export type SpawnFallback = {
export type SpawnWithFallbackResult = {
type SpawnWithFallbackParams = {
export function resolveCommandStdio(params:;
export function formatSpawnError(err: unknown): string;
function shouldRetry(err: unknown, codes: string[]): boolean;
async function spawnAndWaitForSpawn(;
export async function spawnWithFallback(;
