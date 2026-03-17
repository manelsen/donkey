import type { OpenClawConfig, OpenClawPluginApi } from "openclaw/plugin-sdk/thread-ownership";
type ThreadOwnershipConfig = {
type AgentEntry = NonNullable<NonNullable<OpenClawConfig["agents"]>["list"]>[number];
function cleanExpiredMentions(): void;
function resolveOwnershipAgent(config: OpenClawConfig):;
