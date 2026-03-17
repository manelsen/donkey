//! GBNF grammar generation for grammar-constrained tool calling.
//!
//! Generates a GBNF grammar that constrains local LLM output to valid
//! `tool_call` fenced blocks. The grammar allows free text before and after
//! the fenced block, but forces the JSON payload inside the fenced block to
//! conform to the tool schemas.

/// Build a GBNF grammar string that constrains output to either plain text
/// or a fenced `tool_call` block containing valid tool-call JSON.
///
/// The grammar accepts:
///   <free text> ```tool_call\n{"tool": "<name>", "arguments": {<json>}}\n``` <free text>
///
/// `tool_names` is the list of tool names the model may call.
/// An empty list returns `None` (no grammar constraint needed).
#[must_use]
pub fn build_tool_call_grammar(tool_names: &[&str]) -> Option<String> {
    ...
}

#[cfg(test)]
#[allow(clippy::expect_used)]
mod tests {

    #[test]
    fn single_tool_grammar_contains_name() {
    ...
}

    #[test]
    fn multiple_tools_grammar_contains_all_names() {
    ...
}

    #[test]
    fn grammar_has_json_value_rules() {
    ...
}

    #[test]
    fn grammar_has_fenced_block_format() {
    ...
}
}
