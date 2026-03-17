import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { resolveOAuthDir } from "./config/paths.js";
import { logVerbose, shouldLogVerbose } from "./globals.js";
import {
import { isPlainObject } from "./infra/plain-object.js";
export async function ensureDir(dir: string);
/**
 * Check if a file or directory exists at the given path.
 */
export async function pathExists(targetPath: string): Promise<boolean>;
export function clampNumber(value: number, min: number, max: number): number;
export function clampInt(value: number, min: number, max: number): number;
/** Alias for clampNumber (shorter, more common name) */
export const clamp = clampNumber;
/**
 * Escapes special regex characters in a string so it can be used in a RegExp constructor.
 */
export function escapeRegExp(value: string): string;
/**
 * Safely parse JSON, returning null on error instead of throwing.
 */
export function safeParseJson<T>(raw: string): T | null;
export { isPlainObject };
/**
 * Type guard for Record<string, unknown> (less strict than isPlainObject).
 * Accepts any non-null object that isn't an array.
 */
export function isRecord(value: unknown): value is Record<string, unknown>;
export type WebChannel = "web";
export function assertWebChannel(input: string): asserts input is WebChannel;
export function normalizeE164(number: string): string;
/**
 * "Self-chat mode" heuristic (single phone): the gateway is logged in as the owner's own WhatsApp account,
 * and `channels.whatsapp.allowFrom` includes that same number. Used to avoid side-effects that make no sense when the
 * "bot" and the human are the same WhatsApp identity (e.g. auto read receipts, @mention JID triggers).
 */
export function isSelfChatMode(;
export function toWhatsappJid(number: string): string;
export type JidToE164Options = {
type LidLookup = {
function resolveLidMappingDirs(opts?: JidToE164Options): string[];
function readLidReverseMapping(lid: string, opts?: JidToE164Options): string | null;
export function jidToE164(jid: string, opts?: JidToE164Options): string | null;
export async function resolveJidToE164(;
export function sleep(ms: number);
function isHighSurrogate(codeUnit: number): boolean;
function isLowSurrogate(codeUnit: number): boolean;
export function sliceUtf16Safe(input: string, start: number, end?: number): string;
export function truncateUtf16Safe(input: string, maxLen: number): string;
export function resolveUserPath(;
export function resolveConfigDir(;
export function resolveHomeDir(): string | undefined;
function resolveHomeDisplayPrefix():;
export function shortenHomePath(input: string): string;
export function shortenHomeInString(input: string): string;
export function displayPath(input: string): string;
export function displayString(input: string): string;
export function formatTerminalLink(;
export const CONFIG_DIR = resolveConfigDir();
