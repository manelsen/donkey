use {
    moltis_common::types::{MsgContext, ReplyPayload},
    tracing::info,
};

#[cfg(feature = "metrics")]
use moltis_metrics::{auto_reply as auto_reply_metrics, counter, histogram, labels};

/// Main entry point: process an inbound message and produce a reply.
///
/// TODO: load session → parse directives → invoke agent → chunk → return reply
pub async fn get_reply(msg: &MsgContext) -> crate::Result<ReplyPayload> {
    ...
}
