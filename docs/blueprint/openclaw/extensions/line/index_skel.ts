import type { OpenClawPluginApi } from "openclaw/plugin-sdk/line";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/line";
import { registerLineCardCommand } from "./src/card-command.js";
import { linePlugin } from "./src/channel.js";
import { setLineRuntime } from "./src/runtime.js";
export default plugin;
