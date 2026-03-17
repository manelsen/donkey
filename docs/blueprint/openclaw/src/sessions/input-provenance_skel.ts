import type { AgentMessage } from "@mariozechner/pi-agent-core";
export const INPUT_PROVENANCE_KIND_VALUES = [
export type InputProvenanceKind = (typeof INPUT_PROVENANCE_KIND_VALUES)[number];
export type InputProvenance = {
function normalizeOptionalString(value: unknown): string | undefined;
function isInputProvenanceKind(value: unknown): value is InputProvenanceKind;
export function normalizeInputProvenance(value: unknown): InputProvenance | undefined;
export function applyInputProvenanceToUserMessage(;
export function isInterSessionInputProvenance(value: unknown): boolean;
export function hasInterSessionUserProvenance(;
