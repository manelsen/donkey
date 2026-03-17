import { resolveCurrentApiConfig } from './claudeSettings';
import type { CoworkMemoryGuardLevel } from './coworkMemoryExtractor';
import { isQuestionLikeMemoryText } from './coworkMemoryExtractor';

const PROCEDURAL_RE = /(执行以下命令|run\s+(?:the\s+)?following\s+command|\b(?:cd|npm|pnpm|yarn|node|python|bash|sh|git|curl|wget)\b|\$[A-Z_][A-Z0-9_]*|&&|--[a-z0-9-]+|\/tmp\/|\.sh\b|\.bat\b|\.ps1\b)/i;

export interface MemoryJudgeInput {

export interface MemoryJudgeResult {

type CachedLlmJudgeResult = {


function thresholdByGuardLevel(isExplicit: boolean, guardLevel: CoworkMemoryGuardLevel): number {
}

function normalizeText(value: string): string {
}

function clamp01(value: number): number {
}

function shouldCallLlmForBoundaryCase(score: number, threshold: number, reason: string): boolean {
}

function buildLlmCacheKey(input: MemoryJudgeInput): string {
}

function getCachedLlmResult(key: string): MemoryJudgeResult | null {
}

function setCachedLlmResult(key: string, value: MemoryJudgeResult): void {
}

function scoreMemoryText(text: string): { score: number; reason: string } {
}

function buildAnthropicMessagesUrl(baseUrl: string): string {
}

function extractTextFromAnthropicResponse(payload: unknown): string {
}

function parseLlmJudgePayload(text: string): { accepted: boolean; confidence: number; reason: string } | null {
}

async function judgeWithLlm(






    if (!response.ok) {
    }
    if (!parsed || parsed.confidence < LLM_MIN_CONFIDENCE) {
    }


export async function judgeMemoryCandidate(input: MemoryJudgeInput): Promise<MemoryJudgeResult> {
const ruleResult: MemoryJudgeResult;
  if (!input.llmEnabled) {
  }

  if (cached) {
  }

  if (!llmResult) {
  }
