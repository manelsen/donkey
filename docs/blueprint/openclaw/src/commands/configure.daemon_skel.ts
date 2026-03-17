import { withProgress } from "../cli/progress.js";
import { loadConfig } from "../config/config.js";
import { describeGatewayServiceRestart, resolveGatewayService } from "../daemon/service.js";
import { isNonFatalSystemdInstallProbeError } from "../daemon/systemd.js";
import type { RuntimeEnv } from "../runtime.js";
import { note } from "../terminal/note.js";
import { confirm, select } from "./configure.shared.js";
import { buildGatewayInstallPlan, gatewayInstallErrorHint } from "./daemon-install-helpers.js";
import {
import { resolveGatewayInstallToken } from "./gateway-install-token.js";
import { guardCancel } from "./onboard-helpers.js";
import { ensureSystemdUserLingerInteractive } from "./systemd-linger.js";
export async function maybeInstallDaemon(params:;
