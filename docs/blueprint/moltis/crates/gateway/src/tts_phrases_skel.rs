//! Static TTS test phrases for voice onboarding and settings.
//!
//! These match the JS arrays in `tts-phrases.js` and serve as a server-side
//! fallback when the LLM-generated phrase path is unavailable.

/// Return static TTS test phrases personalized with user/bot names.
///
/// `context` should be `"onboarding"` or `"settings"`.
#[must_use]
pub fn static_phrases(user: &str, bot: &str, context: &str) -> Vec<String> {
    ...
}

#[cfg(test)]
mod tests {

    #[test]
    fn test_static_phrases_settings() {
    ...
}

    #[test]
    fn test_static_phrases_unknown_context_uses_settings() {
    ...
}
}
