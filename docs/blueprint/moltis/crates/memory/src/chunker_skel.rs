//! Split markdown text into overlapping chunks by line, targeting a token count.
//!
//! Tokens are approximated as whitespace-split words.

/// A chunk produced by the chunker.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Chunk {
    ...
}

/// Split `text` into chunks of approximately `chunk_size` tokens with `overlap` token overlap.
///
/// Lines are never split mid-line. Each chunk records its 1-based start and end line numbers.
pub fn chunk_markdown(text: &str, chunk_size: usize, overlap: usize) -> Vec<Chunk> {
    ...
}

/// Split content into chunks, using tree-sitter AST splitting when a grammar
/// is available for the given file `extension`, otherwise falling back to
/// the line-based [`chunk_markdown`] splitter.
///
/// This is the primary entry point for chunking; callers should prefer this
/// over calling [`chunk_markdown`] directly.
pub fn chunk_content(
    text: &str,
    chunk_size: usize,
    chunk_overlap: usize,
    extension: &str,
) -> Vec<Chunk> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_single_small_chunk() {
    ...
}

    #[test]
    fn test_multiple_chunks_with_overlap() {
    ...
}

    #[test]
    fn test_line_numbers_are_1_based() {
    ...
}

    #[test]
    fn test_zero_chunk_size() {
    ...
}
}
