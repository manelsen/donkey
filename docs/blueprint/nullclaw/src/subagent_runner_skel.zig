const std = @import("std");
const agent_mod = @import("agent/root.zig");
const config_mod = @import("config.zig");
const config_types = @import("config_types.zig");
const observability = @import("observability.zig");
const provider_names = @import("provider_names.zig");
const providers = @import("providers/root.zig");
const security = @import("security/policy.zig");
const subagent_mod = @import("subagent.zig");
const tools_mod = @import("tools/root.zig");
const memory_mod = @import("memory/root.zig");
const bootstrap_mod = @import("bootstrap/root.zig");


/// Execute a spawned subagent task with the full agent tool loop, constrained
/// to the restricted `subagentTools` tool set.
    const provider_entry = findProviderEntry(request.default_provider, request.configured_providers);
    const provider_base_url = if (provider_entry) |entry| entry.base_url else null;
    const provider_native_tools = if (provider_entry) |entry| entry.native_tools else true;
    const provider_user_agent = if (provider_entry) |entry| entry.user_agent else null;


    var tracker = security.RateTracker.init(allocator, request.max_actions_per_hour);

    var mem_rt = memory_mod.initRuntime(allocator, &request.memory_config, request.workspace_dir);
    const mem_opt: ?memory_mod.Memory = if (mem_rt) |rt| rt.memory else null;



    const effective_model = request.default_model orelse "anthropic/claude-sonnet-4";

    var noop_obs = observability.NoopObserver{

test "findProviderEntry matches case-insensitively" {
    const found = findProviderEntry("customgw", &entries) orelse return error.TestUnexpectedResult;

test "findProviderEntry matches provider aliases" {
    const found = findProviderEntry("AZURE-OPENAI", &entries) orelse return error.TestUnexpectedResult;
