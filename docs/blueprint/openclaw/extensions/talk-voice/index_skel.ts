import type { OpenClawPluginApi } from "openclaw/plugin-sdk/talk-voice";
type ElevenLabsVoice = {
function mask(s: string, keep: number = 6): string;
function isLikelyVoiceId(value: string): boolean;
async function listVoices(apiKey: string): Promise<ElevenLabsVoice[]>;
function formatVoiceList(voices: ElevenLabsVoice[], limit: number): string;
function findVoice(voices: ElevenLabsVoice[], query: string): ElevenLabsVoice | null;
function asTrimmedString(value: unknown): string;
function resolveCommandLabel(channel: string): string;
