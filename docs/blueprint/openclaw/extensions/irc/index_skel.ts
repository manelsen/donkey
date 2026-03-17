import type { ChannelPlugin, OpenClawPluginApi } from "openclaw/plugin-sdk/irc";
import { emptyPluginConfigSchema } from "openclaw/plugin-sdk/irc";
import { ircPlugin } from "./src/channel.js";
import { setIrcRuntime } from "./src/runtime.js";
export default plugin;
