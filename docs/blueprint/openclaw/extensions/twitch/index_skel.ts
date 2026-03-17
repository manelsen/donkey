import type { OpenClawPluginApi } from "openclaw/plugin-sdk/twitch";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/twitch";
import { twitchPlugin } from "./src/plugin.js";
import { setTwitchRuntime } from "./src/runtime.js";
export { monitorTwitchProvider } from "./src/monitor.js";
export default plugin;
