//! Chat template formatting for various model families.
//!
//! Different LLM families use different prompt formats. This module provides
//! template formatting for Llama3, ChatML (Qwen/Kimi), Mistral, and DeepSeek.

use moltis_agents::model::{ChatMessage, UserContent};

/// Hint for which chat template to use.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ChatTemplateHint {
    ...
}

impl ChatTemplateHint {
    /// Parse from string (for config).
    #[must_use]
    pub fn parse(s: &str) -> Self {
}

/// Extract role and content strings from a `ChatMessage`.
fn role_content(msg: &ChatMessage) -> (&str, &str) {
    ...
}

/// Format messages using the specified chat template.
#[must_use]
pub fn format_messages(messages: &[ChatMessage], hint: ChatTemplateHint) -> String {
    ...
}

/// Format using ChatML template (Qwen, Kimi, Yi).
///
/// ```text
/// <|im_start|>system
/// {system_message}<|im_end|>
/// <|im_start|>user
/// {user_message}<|im_end|>
/// <|im_start|>assistant
/// ```
fn format_chatml(messages: &[ChatMessage]) -> String {
    ...
}

/// Format using Llama 3 template.
///
/// ```text
/// <|begin_of_text|><|start_header_id|>system<|end_header_id|>
///
/// {system_message}<|eot_id|><|start_header_id|>user<|end_header_id|>
///
/// {user_message}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
/// ```
fn format_llama3(messages: &[ChatMessage]) -> String {
    ...
}

/// Format using Mistral template.
///
/// ```text
/// <s>[INST] {system_message}
///
/// {user_message} [/INST]
/// ```
fn format_mistral(messages: &[ChatMessage]) -> String {
    ...
}

/// Format using DeepSeek template (similar to ChatML).
///
/// ```text
/// <|begin▁of▁sentence|>system
/// {system_message}
/// <|User|>{user_message}
/// <|Assistant|>
/// ```
fn format_deepseek(messages: &[ChatMessage]) -> String {
    ...
}

#[cfg(test)]
mod tests {

    fn multi_turn_messages() -> Vec<ChatMessage> {
    ...
}

    #[test]
    fn test_chatml_format() {
    ...
}

    #[test]
    fn test_chatml_multi_turn() {
    ...
}

    #[test]
    fn test_llama3_format() {
    ...
}

    #[test]
    fn test_mistral_format() {
    ...
}

    #[test]
    fn test_mistral_multi_turn() {
    ...
}

    #[test]
    fn test_deepseek_format() {
    ...
}

    #[test]
    fn test_format_messages_dispatch() {
    ...
}

    #[test]
    fn test_chat_template_hint_parse() {
    ...
}

    #[test]
    fn test_empty_messages() {
    ...
}
}
