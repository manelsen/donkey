import os from "node:os";
import type { OpenClawPluginApi } from "openclaw/plugin-sdk/device-pair";
import {
import qrcode from "qrcode-terminal";
import {
function renderQrAscii(data: string): Promise<string>;
type DevicePairPluginConfig = {
type SetupPayload = {
type ResolveUrlResult = {
type ResolveAuthLabelResult = {
function normalizeUrl(raw: string, schemeFallback: "ws" | "wss"): string | null;
function parseNormalizedGatewayUrl(raw: string): string | null;
function parsePositiveInteger(raw: string | undefined): number | null;
function resolveGatewayPort(cfg: OpenClawPluginApi["config"]): number;
function resolveScheme(;
function parseIPv4Octets(address: string): [number, number, number, number] | null;
function isPrivateIPv4(address: string): boolean;
function isTailnetIPv4(address: string): boolean;
function pickMatchingIPv4(predicate: (address: string) => boolean): string | null;
function pickLanIPv4(): string | null;
function pickTailnetIPv4(): string | null;
async function resolveTailnetHost(): Promise<string | null>;
function resolveAuthLabel(cfg: OpenClawPluginApi["config"]): ResolveAuthLabelResult;
function pickFirstDefined(candidates: Array<unknown>): string | null;
function resolveRequiredAuthLabel(;
async function resolveGatewayUrl(api: OpenClawPluginApi): Promise<ResolveUrlResult>;
function encodeSetupCode(payload: SetupPayload): string;
function formatSetupReply(payload: SetupPayload, authLabel: string): string;
function formatSetupInstructions(): string;
