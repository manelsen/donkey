use {crate::Result, moltis_common::types::MsgContext};

/// Resolved route: which agent handles this message and the session key.
#[derive(Debug, Clone)]
pub struct ResolvedRoute {
    ...
}

/// Resolve which agent should handle a message, following the binding cascade.
pub fn resolve_agent_route(
    _msg: &MsgContext,
    _config: &serde_json::Value,
) -> Result<ResolvedRoute> {
    ...
}
