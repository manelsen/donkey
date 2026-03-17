import type { ChannelPlugin, OpenClawPluginApi } from "openclaw/plugin-sdk/core";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/core";
import { telegramPlugin } from "./src/channel.js";
import { setTelegramRuntime } from "./src/runtime.js";
export default plugin;
