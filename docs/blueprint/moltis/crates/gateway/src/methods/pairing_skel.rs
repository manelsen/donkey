use moltis_protocol::{ErrorShape, error_codes};

use crate::broadcast::{BroadcastOpts, broadcast};

use super::MethodRegistry;

/// Helper to get the pairing store, falling back to in-memory state.
fn get_pairing_store(
    state: &crate::state::GatewayState,
) -> Option<&std::sync::Arc<crate::pairing::PairingStore>> {
    ...
}

pub(super) fn register(reg: &mut MethodRegistry) {
    ...
}
