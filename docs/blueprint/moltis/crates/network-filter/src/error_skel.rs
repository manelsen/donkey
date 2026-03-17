use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    ...
}

impl Error {
    #[must_use]
    pub fn message(msg: impl Into<String>) -> Self {
}

pub type Result<T> = std::result::Result<T, Error>;

#[cfg(test)]
#[allow(clippy::unwrap_used)]
mod tests {

    #[test]
    fn json_error_converts() {
    ...
}

    #[test]
    fn message_error() {
    ...
}
}
