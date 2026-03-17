/** Wrap text with an OSC 8 terminal hyperlink. */
export function wrapOsc8(url: string, text: string): string;
/**
 * Extract all unique URLs from raw markdown text.
 * Finds both bare URLs and markdown link hrefs [text](url).
 */
export function extractUrls(markdown: string): string[];
/** Strip ANSI SGR and OSC 8 sequences to get visible text. */
function stripAnsi(input: string): string;
interface UrlRange {
/**
 * Find URL ranges in a line's visible text, handling cross-line URL splits.
 */
function findUrlRanges(;
/**
 * Apply OSC 8 hyperlink sequences to a line based on visible-text URL ranges.
 * Walks through the raw string character by character, inserting OSC 8
 * open/close sequences at URL range boundaries while preserving ANSI codes.
 */
function applyOsc8Ranges(line: string, ranges: UrlRange[]): string;
/**
 * Add OSC 8 hyperlinks to rendered lines using a pre-extracted URL list.
 *
 * For each line, finds URL-like substrings in the visible text, matches them
 * against known URLs, and wraps each fragment with OSC 8 escape sequences.
 * Handles URLs broken across multiple lines by pi-tui's word wrapping.
 */
export function addOsc8Hyperlinks(lines: string[], urls: string[]): string[];
