use {
    serde::{Deserialize, Serialize},
    tracing::debug,
};

/// Glob-based allow/deny policy for tool access.
#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct ToolPolicy {
    ...
}

/// Context for resolving which policy layers apply.
#[derive(Debug, Clone, Default)]
pub struct PolicyContext {
    ...
}

/// Predefined tool profiles.
pub fn profile_tools(profile: &str) -> ToolPolicy {
    ...
}

/// Check if a tool name matches a glob pattern (supports `*` wildcard).
fn pattern_matches(pattern: &str, name: &str) -> bool {
    ...
}

impl ToolPolicy {
    /// Returns true if the given tool name is allowed by this policy.
    /// Deny always wins over allow.
    pub fn is_allowed(&self, tool_name: &str) -> bool {

    /// Merge another policy on top of this one (the `other` has higher precedence).
    /// Non-empty lists from `other` replace those from `self`.
    pub fn merge_with(&self, other: &ToolPolicy) -> ToolPolicy {
    ...
}
}

/// Resolve the effective policy by merging layers from config.
///
/// Layer precedence (later wins for allow, deny always accumulates):
/// 1. Global
/// 2. Per-provider
/// 3. Per-agent
/// 4. Per-group
/// 5. Per-sender in group
/// 6. Sandbox-specific
pub fn resolve_effective_policy(config: &serde_json::Value, context: &PolicyContext) -> ToolPolicy {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_deny_wins() {
    ...
}

    #[test]
    fn test_prefix_pattern() {
    ...
}

    #[test]
    fn test_empty_allow_permits_all() {
    ...
}

    #[test]
    fn test_merge_deny_accumulates() {
    ...
}

    #[test]
    fn test_profiles() {
    ...
}

    #[test]
    fn test_resolve_global_policy() {
    ...
}

    #[test]
    fn test_resolve_deny_wins_across_layers() {
    ...
}
}
