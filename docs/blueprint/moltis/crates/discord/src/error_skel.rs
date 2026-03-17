use moltis_channels::Error as ChannelError;

/// Errors specific to the Discord channel plugin.
#[derive(Debug, thiserror::Error)]
pub enum Error {
    ...
}

impl From<Error> for ChannelError {
    fn from(err: Error) -> Self {
}
