import { listChannelPlugins } from "../channels/plugins/index.js";
import type { ChannelAccountSnapshot, ChannelPlugin } from "../channels/plugins/types.js";
import type { OpenClawConfig } from "../config/config.js";
import { resolveDefaultChannelAccountContext } from "./channel-account-context.js";
export type LinkChannelContext = {
export async function resolveLinkChannelContext(;
