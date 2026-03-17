import { resolveNodeService } from "../daemon/node-service.js";
import { resolveGatewayService } from "../daemon/service.js";
import { formatDaemonRuntimeShort } from "./status.format.js";
import { readServiceStatusSummary } from "./status.service-summary.js";
type DaemonStatusSummary = {
async function buildDaemonStatusSummary(;
export async function getDaemonStatusSummary(): Promise<DaemonStatusSummary>;
export async function getNodeDaemonStatusSummary(): Promise<DaemonStatusSummary>;
