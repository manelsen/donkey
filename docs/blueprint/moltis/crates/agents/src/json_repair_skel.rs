//! Best-effort JSON repair for malformed model output.
//!
//! Small models sometimes produce JSON with trailing commas, unbalanced braces,
//! or `//` comments. This module tries to salvage the value without pulling in
//! a heavy dependency.

/// Attempt to parse `input` as JSON, applying simple repairs when the initial
/// parse fails.
///
/// Repairs applied (in order):
/// 1. Strip `//` line comments.
/// 2. Remove trailing commas before `}` or `]`.
/// 3. Balance unclosed braces/brackets by appending the missing closers.
///
/// Returns `None` if the input cannot be salvaged.
pub fn repair_json(input: &str) -> Option<serde_json::Value> {
    ...
}
    let mut cleaned = String::with_capacity(buf.len());
    let bytes = buf.as_bytes();
    let mut i = 0;
    in_string = false;
    let mut escape_next = false;
    while i < bytes.len() {
        let b = bytes[i];
        if in_string {
            cleaned.push(b as char);
            if escape_next {
                escape_next = false;
            } else if b == b'\\' {
                escape_next = true;
            } else if b == b'"' {
                in_string = false;
            }
            i += 1;
            continue;
        }
        if b == b'"' {
            in_string = true;
            cleaned.push(b as char);
            i += 1;
            continue;
        }
        if b == b',' {
            // Look ahead past whitespace for } or ].
            let mut j = i + 1;
            while j < bytes.len() && bytes[j].is_ascii_whitespace() {
                j += 1;
            }
            if j < bytes.len() && (bytes[j] == b'}' || bytes[j] == b']') {
                // Skip the trailing comma.
                i += 1;
                continue;
            }
        }
        cleaned.push(b as char);
        i += 1;
    }

    // Try parse after comment/comma cleanup.
    if let Ok(v) = serde_json::from_str(&cleaned) {
        return Some(v);
    }

    // Pass 3: balance unclosed braces/brackets.
    let mut stack: Vec<char> = Vec::new();
    in_string = false;
    escape_next = false;
    for ch in cleaned.chars() {
        if in_string {
            if escape_next {
                escape_next = false;
            } else if ch == '\\' {
                escape_next = true;
            } else if ch == '"' {
                in_string = false;
            }
            continue;
        }
        match ch {
            '"' => in_string = true,
            '{' => stack.push('}'),
            '[' => stack.push(']'),
            '}' | ']' => {
                if stack.last() == Some(&ch) {
                    stack.pop();
                }
            },
            _ => {},
        }
    }

    // Close any string that's still open.
    if in_string {
        cleaned.push('"');
    }
    // Append missing closers in reverse order.
    while let Some(closer) = stack.pop() {
        cleaned.push(closer);
    }

    serde_json::from_str(&cleaned).ok()
}

#[allow(clippy::unwrap_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn trailing_comma_object() {
    ...
}

    #[test]
    fn trailing_comma_array() {
    ...
}

    #[test]
    fn line_comments_stripped() {
    ...
}

    #[test]
    fn unbalanced_braces() {
    ...
}