type MinimalTheme = {
export const defaultWaitingPhrases = [
export function pickWaitingPhrase(tick: number, phrases = defaultWaitingPhrases);
export function shimmerText(theme: MinimalTheme, text: string, tick: number);
export function buildWaitingStatusMessage(params:;
