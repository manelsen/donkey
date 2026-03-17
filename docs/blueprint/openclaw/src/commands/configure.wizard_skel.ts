import fsPromises from "node:fs/promises";
import nodePath from "node:path";
import { formatCliCommand } from "../cli/command-format.js";
import type { OpenClawConfig } from "../config/config.js";
import { readConfigFileSnapshot, resolveGatewayPort, writeConfigFile } from "../config/config.js";
import { logConfigUpdated } from "../config/logging.js";
import { ensureControlUiAssetsBuilt } from "../infra/control-ui-assets.js";
import type { RuntimeEnv } from "../runtime.js";
import { defaultRuntime } from "../runtime.js";
import { note } from "../terminal/note.js";
import { resolveUserPath } from "../utils.js";
import { createClackPrompter } from "../wizard/clack-prompter.js";
import { WizardCancelledError } from "../wizard/prompts.js";
import { resolveSetupSecretInputString } from "../wizard/setup.secret-input.js";
import { removeChannelConfigWizard } from "./configure.channels.js";
import { maybeInstallDaemon } from "./configure.daemon.js";
import { promptAuthConfig } from "./configure.gateway-auth.js";
import { promptGatewayConfig } from "./configure.gateway.js";
import type {
import {
import { formatHealthCheckFailure } from "./health-format.js";
import { healthCommand } from "./health.js";
import { noteChannelStatus, setupChannels } from "./onboard-channels.js";
import {
import { promptRemoteGatewayConfig } from "./onboard-remote.js";
import { setupSkills } from "./onboard-skills.js";
type ConfigureSectionChoice = WizardSection | "__continue";
async function resolveGatewaySecretInputForWizard(params:;
async function runGatewayHealthCheck(params:;
async function promptConfigureSection(;
async function promptChannelMode(runtime: RuntimeEnv): Promise<ChannelsWizardMode>;
async function promptWebToolsConfig(;
export async function runConfigureWizard(;
