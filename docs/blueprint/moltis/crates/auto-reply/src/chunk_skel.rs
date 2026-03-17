/// Split long agent responses to fit channel message size limits.
pub fn chunk_response(text: &str, max_len: usize) -> Vec<String> {
    ...
}
