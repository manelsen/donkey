import fs from "node:fs";
import { loadConfig } from "../config/config.js";
import {
import type { RuntimeEnv } from "../runtime.js";
import { isRich, theme } from "../terminal/theme.js";
import {
import {
export type SessionsCleanupOptions = {
type SessionCleanupAction =
type SessionCleanupActionRow = ReturnType<typeof toSessionDisplayRows>[number] & {
type SessionCleanupSummary = {
function resolveSessionCleanupAction(params:;
function formatCleanupActionCell(action: SessionCleanupAction, rich: boolean): string;
function buildActionRows(params:;
function pruneMissingTranscriptEntries(params:;
async function previewStoreCleanup(params:;
function renderStoreDryRunPlan(params:;
export async function sessionsCleanupCommand(opts: SessionsCleanupOptions, runtime: RuntimeEnv);
