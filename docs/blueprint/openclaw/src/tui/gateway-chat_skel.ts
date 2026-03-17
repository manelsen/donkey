import { randomUUID } from "node:crypto";
import { loadConfig } from "../config/config.js";
import { hasConfiguredSecretInput } from "../config/types.secrets.js";
import { assertExplicitGatewayAuthModeWhenBothConfigured } from "../gateway/auth-mode-policy.js";
import {
import { GatewayClient } from "../gateway/client.js";
import { GATEWAY_CLIENT_CAPS } from "../gateway/protocol/client-info.js";
import {
import { resolveConfiguredSecretInputString } from "../gateway/resolve-configured-secret-input-string.js";
import { GATEWAY_CLIENT_MODES, GATEWAY_CLIENT_NAMES } from "../utils/message-channel.js";
import { VERSION } from "../version.js";
import type { ResponseUsageMode, SessionInfo, SessionScope } from "./tui-types.js";
export type GatewayConnectionOptions = {
export type ChatSendOptions = {
export type GatewayEvent = {
type ResolvedGatewayConnection = {
function trimToUndefined(value: unknown): string | undefined;
function throwGatewayAuthResolutionError(reason: string): never;
export type GatewaySessionList = {
export type GatewayAgentsList = {
export type GatewayModelChoice = {
export class GatewayChatClient {
export async function resolveGatewayConnection(;
