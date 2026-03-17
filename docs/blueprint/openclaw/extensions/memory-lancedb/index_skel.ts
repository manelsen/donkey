/**
 * OpenClaw Memory (LanceDB) Plugin
 *
 * Long-term memory with vector search for AI conversations.
 * Uses LanceDB for storage and OpenAI for embeddings.
 * Provides seamless auto-recall and auto-capture via lifecycle hooks.
 */
import { randomUUID } from "node:crypto";
import type * as LanceDB from "@lancedb/lancedb";
import { Type } from "@sinclair/typebox";
import OpenAI from "openai";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/memory-lancedb";
import {
type MemoryEntry = {
type MemorySearchResult = {
class MemoryDB {
class Embeddings {
export function looksLikePromptInjection(text: string): boolean;
export function escapeMemoryForPrompt(text: string): string;
export function formatRelevantMemoriesContext(;
export function shouldCapture(text: string, options?:;
export function detectCategory(text: string): MemoryCategory;
export default memoryPlugin;
