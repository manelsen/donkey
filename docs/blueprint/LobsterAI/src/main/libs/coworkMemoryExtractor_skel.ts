const EXPLICIT_ADD_RE = /(?:^|\n)\s*(?:请)?(?:记住|记下|保存到记忆|保存记忆|写入记忆|remember(?:\s+this|\s+that)?|store\s+(?:this|that)\s+in\s+memory)\s*[:：,，]?\s*(.+)$/gim;
const PERSONAL_OWNERSHIP_SIGNAL_RE = /(我有(?!\s*(?:一个|个)?问题)|我养了|我家有|我女儿|我儿子|我的孩子|我的小狗|我的小猫|\bi\s+have\b|\bi\s+own\b|\bmy\s+(?:daughter|son|child|dog|cat)\b)/i;
const PROCEDURAL_CANDIDATE_RE = /(执行以下命令|run\s+(?:the\s+)?following\s+command|\b(?:cd|npm|pnpm|yarn|node|python|bash|sh|git|curl|wget)\b|\$[A-Z_][A-Z0-9_]*|&&|--[a-z0-9-]+|\/tmp\/|\.sh\b|\.bat\b|\.ps1\b)/i;
const ENGLISH_QUESTION_PREFIX_RE = /^(?:what|who|why|how|when|where|which|is|are|am|do|does|did|can|could|would|will|should)\b/i;

export type CoworkMemoryGuardLevel = 'strict' | 'standard' | 'relaxed';

export interface ExtractedMemoryChange {

export interface ExtractTurnMemoryOptions {

function normalizeText(value: string): string {
}

export function isQuestionLikeMemoryText(text: string): boolean {

function shouldKeepCandidate(text: string): boolean {
}

function sanitizeImplicitCandidate(text: string): string {
}

function confidenceThreshold(level: CoworkMemoryGuardLevel): number {
}

function extractExplicit(
const result: ExtractedMemoryChange[];
let match: RegExpExecArray | null;

function extractImplicit(options: ExtractTurnMemoryOptions): ExtractedMemoryChange[] {
}

export function extractTurnMemoryChanges(options: ExtractTurnMemoryOptions): ExtractedMemoryChange[] {

  const explicitAdds = extractExplicit(userText, 'add', EXPLICIT_ADD_RE, 'explicit:add-command');
  const explicitDeletes = extractExplicit(userText, 'delete', EXPLICIT_DELETE_RE, 'explicit:delete-command');

const merged: ExtractedMemoryChange[];
  for (const entry of [...explicitDeletes, ...explicitAdds, ...implicitAdds]) {
  }

