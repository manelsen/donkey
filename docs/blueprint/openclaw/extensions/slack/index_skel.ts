import type { OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/core";
import { slackPlugin } from "./src/channel.js";
import { setSlackRuntime } from "./src/runtime.js";
export default plugin;
