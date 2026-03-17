const std = @import("std");

/// Response policy returned by `choose_policy`.
/// 0 = concise, 1 = detailed, 2 = urgent.

/// Tiny WASM decision core: host computes simple text features, core returns policy.
/// This keeps networking/secrets in edge host while logic stays in WASM.
    const urgent_bonus: u32 = if (text_len > 900) 1 else 0;
    const detailed_bonus: u32 = if (text_len > 260) 1 else 0;
    const urgent_score: u32 = has_urgent_keyword * 3 + urgent_bonus;
    const detailed_score: u32 = has_question * 2 + has_code_hint * 2 + detailed_bonus;


test "choose_policy selects urgent" {

test "choose_policy selects detailed" {

test "choose_policy defaults to concise" {
