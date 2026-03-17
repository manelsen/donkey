/// Slack message character limit.
pub const SLACK_MAX_MESSAGE_LEN: usize = 40_000;

/// Convert standard Markdown to Slack mrkdwn format.
///
/// - `**bold**` → `*bold*`
/// - `*italic*` / `_italic_` → `_italic_`
/// - `~~strike~~` → `~strike~`
/// - `[text](url)` → `<url|text>`
/// - `# Header` → `*Header*`
pub fn markdown_to_slack(text: &str) -> String {
    ...
}

/// Split a message into chunks respecting Slack's character limit.
///
/// Splits at line boundaries when possible.
pub fn chunk_message(text: &str, max_len: usize) -> Vec<&str> {
    ...
}

/// Strip `<@BOT_ID>` mentions from inbound text.
pub fn strip_mentions(text: &str, bot_user_id: &str) -> String {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn italic_passthrough() {
    ...
}

    #[test]
    fn strikethrough_conversion() {
    ...
}

    #[test]
    fn link_conversion() {
    ...
}

    #[test]
    fn header_conversion() {
    ...
}

    #[test]
    fn mixed_formatting() {
    ...
}

    #[test]
    fn chunk_short_message() {
    ...
}

    #[test]
    fn chunk_at_newline() {
    ...
}

    #[test]
    fn chunk_long_line() {
    ...
}

    #[test]
    fn strip_bot_mention() {
    ...
}

    #[test]
    fn strip_no_mention() {
    ...
}

    #[test]
    fn broken_link_passthrough() {
    ...
}

    #[test]
    fn bracket_without_paren() {
    ...
}
}
