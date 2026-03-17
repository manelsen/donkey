use crate::broadcast::{BroadcastOpts, broadcast};

use super::MethodRegistry;

pub(super) fn register(reg: &mut MethodRegistry) {
    ...
}

/// Core protocol method names for `system.describe`.
///
/// This is a static subset of methods registered in `gateway.rs`, `node.rs`,
/// `subscribe.rs`, and `channel_mux.rs`. The full method list (including all
/// service methods) is already available in `HelloOk.features.methods`.
///
/// TODO: store Arc<MethodRegistry> on GatewayState so this handler can query
/// the live registry instead of maintaining a static list.
fn reg_method_names() -> Vec<&'static str> {
    ...
}
