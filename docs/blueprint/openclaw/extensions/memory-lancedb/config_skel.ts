import fs from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
export type MemoryConfig = {
export const MEMORY_CATEGORIES = ["preference", "fact", "decision", "entity", "other"] as const;
export type MemoryCategory = (typeof MEMORY_CATEGORIES)[number];
export const DEFAULT_CAPTURE_MAX_CHARS = 500;
function resolveDefaultDbPath(): string;
function assertAllowedKeys(value: Record<string, unknown>, allowed: string[], label: string);
export function vectorDimsForModel(model: string): number;
function resolveEnvVars(value: string): string;
function resolveEmbeddingModel(embedding: Record<string, unknown>): string;
export const memoryConfigSchema = {
