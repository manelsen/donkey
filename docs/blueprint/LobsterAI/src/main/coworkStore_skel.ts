import { app } from 'electron';
import crypto from 'crypto';
import fs from 'fs';
import os from 'os';
import path from 'path';
import { Database } from 'sql.js';
import { v4 as uuidv4 } from 'uuid';
import {
  type CoworkMemoryGuardLevel,
import { judgeMemoryCandidate } from './libs/coworkMemoryJudge';

// Default working directory for new users
const getDefaultWorkingDirectory = (): string => {


const normalizeRecentWorkspacePath = (cwd: string): string => {
  if (markerIndex > 0) {
  }

const DEFAULT_MEMORY_GUARD_LEVEL: CoworkMemoryGuardLevel;
const MEMORY_PROCEDURAL_TEXT_RE = /(执行以下命令|run\s+(?:the\s+)?following\s+command|\b(?:cd|npm|pnpm|yarn|node|python|bash|sh|git|curl|wget)\b|\$[A-Z_][A-Z0-9_]*|&&|--[a-z0-9-]+|\/tmp\/|\.sh\b|\.bat\b|\.ps1\b)/i;

function normalizeMemoryGuardLevel(value: string | undefined): CoworkMemoryGuardLevel {
}

function parseBooleanConfig(value: string | undefined, fallback: boolean): boolean {
}

function clampMemoryUserMemoriesMaxItems(value: number): number {
}

function normalizeMemoryText(value: string): string {
}

function extractConversationSearchTerms(value: string): string[] {
}

function normalizeMemoryMatchKey(value: string): string {
}

function normalizeMemorySemanticKey(value: string): string {
}

function buildTokenFrequencyMap(value: string): Map<string, number> {
}

function scoreTokenOverlap(left: string, right: string): number {
}

function buildCharacterBigramMap(value: string): Map<string, number> {
}

function scoreCharacterBigramDice(left: string, right: string): number {
}

function scoreMemorySimilarity(left: string, right: string): number {
}

function scoreMemoryTextQuality(value: string): number {
}

function choosePreferredMemoryText(currentText: string, incomingText: string): string {
}

function isMeaningfulDeleteFragment(value: string): boolean {
}

function includesAsBoundedPhrase(target: string, fragment: string): boolean {
}

function scoreDeleteMatch(targetKey: string, queryKey: string): number {
}

function buildMemoryFingerprint(text: string): string {
}

function truncate(value: string, maxChars: number): string {
}

function parseTimeToMs(input?: string | null): number | null {
}

function shouldAutoDeleteMemoryText(text: string): boolean {
}

// Types mirroring src/types/cowork.ts for main process use
export type CoworkSessionStatus = 'idle' | 'running' | 'completed' | 'error';
export type CoworkMessageType = 'user' | 'assistant' | 'tool_use' | 'tool_result' | 'system';
export type CoworkExecutionMode = 'auto' | 'local' | 'sandbox';

export interface CoworkMessageMetadata {

export interface CoworkMessage {

export interface CoworkSession {

export interface CoworkSessionSummary {

export type CoworkUserMemoryStatus = 'created' | 'stale' | 'deleted';

export interface CoworkUserMemory {

export interface CoworkUserMemorySource {

export interface CoworkUserMemorySourceInput {

export interface CoworkUserMemoryStats {

export interface CoworkConversationSearchRecord {

export interface CoworkConfig {

export type CoworkConfigUpdate = Partial<Pick<

export interface ApplyTurnMemoryUpdatesOptions {

export interface ApplyTurnMemoryUpdatesResult {

let cachedDefaultSystemPrompt: string | null;

const getDefaultSystemPrompt = (): string => {
  if (cachedDefaultSystemPrompt !== null) {
  }



interface CoworkMessageRow {

interface CoworkUserMemoryRow {

export class CoworkStore {


const row: Record<string, unknown>;

const row: Record<string, unknown>;





  getSession(id: string): CoworkSession | null {
  }

const setClauses: string[];

    if (updates.title !== undefined) {
    }
    if (updates.claudeSessionId !== undefined) {
    }
    if (updates.status !== undefined) {
    }
    if (updates.cwd !== undefined) {
    }
    if (updates.systemPrompt !== undefined) {
    }
    if (updates.executionMode !== undefined) {
    }



  deleteSession(id: string): void {
  }

  deleteSessions(ids: string[]): void {
  }

  setSessionPinned(id: string, pinned: boolean): void {
  }

  listSessions(): CoworkSessionSummary[] {
  }

  resetRunningSessions(): number {
  }

  listRecentCwds(limit: number = 8): string[] {
  }

  private getSessionMessages(sessionId: string): CoworkMessage[] {
  }

  addMessage(sessionId: string, message: Omit<CoworkMessage, 'id' | 'timestamp'>): CoworkMessage {
  }

  updateMessage(sessionId: string, messageId: string, updates: { content?: string; metadata?: CoworkMessageMetadata }): void {
  }

  // Config operations
  getConfig(): CoworkConfig {
  }

  setConfig(config: CoworkConfigUpdate): void {
  }

  getAppLanguage(): 'zh' | 'en' {
  }

  private mapMemoryRow(row: CoworkUserMemoryRow): CoworkUserMemory {
  }

  private addMemorySource(memoryId: string, source?: CoworkUserMemorySourceInput): void {
  }

    if (!normalizedText) {
    }

    const confidence = Math.max(0, Math.min(1, Number.isFinite(input.confidence) ? Number(input.confidence) : 0.75));
    const explicitFlag = input.isExplicit ? 1 : 0;


    if (!existing) {
    }

    if (existing) {
    }


    if (!memory) {
    }



const clauses: string[];
const params: Array<string | number>;

    if (!includeDeleted && status === 'all') {
    }
    if (status !== 'all') {
    }
    if (query) {
    }






    const nextText = input.text !== undefined ? truncate(normalizeMemoryText(input.text), 360) : current.text;
    if (!nextText) {
    }
    const nextExplicit = input.isExplicit !== undefined ? (input.isExplicit ? 1 : 0) : current.is_explicit;




  deleteUserMemory(id: string): boolean {
  }

  getUserMemoryStats(): CoworkUserMemoryStats {
  }

  autoDeleteNonPersonalMemories(): number {
  }

  markMemorySourcesInactiveBySession(sessionId: string): void {
  }

  markOrphanImplicitMemoriesStale(): void {
  }

  async applyTurnMemoryUpdates(options: ApplyTurnMemoryUpdatesOptions): Promise<ApplyTurnMemoryUpdatesResult> {
  }

  private getLatestMessageByType(sessionId: string, type: 'user' | 'assistant'): string {
  }



const clauses: string[];
const params: Array<string | number>;

    if (beforeMs !== null) {
    }
    if (afterMs !== null) {
    }


    for (const row of rows) {
    }




const clauses: string[];
const params: Array<string | number>;

    if (beforeMs !== null) {
    }
    if (afterMs !== null) {
    }



