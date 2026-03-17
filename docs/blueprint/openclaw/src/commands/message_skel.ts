import {
import { resolveCommandSecretRefsViaGateway } from "../cli/command-secret-gateway.js";
import { getChannelsCommandSecretTargetIds } from "../cli/command-secret-targets.js";
import { createOutboundSendDeps, type CliDeps } from "../cli/outbound-send-deps.js";
import { withProgress } from "../cli/progress.js";
import { loadConfig } from "../config/config.js";
import type { OutboundSendDeps } from "../infra/outbound/deliver.js";
import { runMessageAction } from "../infra/outbound/message-action-runner.js";
import type { RuntimeEnv } from "../runtime.js";
import { GATEWAY_CLIENT_MODES, GATEWAY_CLIENT_NAMES } from "../utils/message-channel.js";
import { buildMessageCliJson, formatMessageCliText } from "./message-format.js";
export async function messageCommand(;
