export type ParsedLogLine = {
function extractMessage(value: Record<string, unknown>): string;
function parseMetaName(raw?: unknown):;
export function parseLogLine(raw: string): ParsedLogLine | null;
