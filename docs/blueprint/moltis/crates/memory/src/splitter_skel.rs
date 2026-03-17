//! AST-aware code splitting via tree-sitter, with fallback to line-based chunking.
//!
//! When the `code-splitter-base` feature is enabled and a grammar is available for
//! the file extension, content is split at AST boundaries (functions, classes, structs)
//! using the `text-splitter` crate. Otherwise, falls back to [`chunk_markdown`].

use crate::chunker::{Chunk, chunk_markdown};

/// Average characters per word, used to convert word-count config to character count.
const CHARS_PER_WORD: usize = 5;

/// Split content into chunks, using tree-sitter when a grammar is available for `extension`.
///
/// `chunk_size` and `chunk_overlap` are in **words** (matching existing config semantics).
/// For tree-sitter splitting these are converted to approximate character counts.
pub fn chunk_content(
    text: &str,
    chunk_size: usize,
    chunk_overlap: usize,
    extension: &str,
) -> Vec<Chunk> {
    ...
}

/// Attempt to split with tree-sitter. Returns `None` if no grammar is available.
#[cfg(feature = "code-splitter-base")]
fn try_code_split(
    text: &str,
    chunk_size: usize,
    chunk_overlap: usize,
    extension: &str,
) -> Option<Vec<Chunk>> {
    ...
}

/// Build a [`CodeSplitter`] for the given file extension, if a grammar is available.
///
/// Each match arm is gated behind the corresponding `lang-*` feature.
#[cfg(feature = "code-splitter-base")]
fn build_code_splitter(
    ext: &str,
    config: text_splitter::ChunkConfig<text_splitter::Characters>,
) -> Option<text_splitter::CodeSplitter<text_splitter::Characters>> {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn empty_input_returns_empty() {
    ...
}

    #[test]
    fn single_line_content() {
    ...
}

    #[test]
    fn content_smaller_than_chunk_size() {
    ...
}

    #[cfg(feature = "lang-rust")]
    #[test]
    fn rust_function_boundaries_preserved() {
    ...
}

    #[cfg(feature = "lang-python")]
    #[test]
    fn python_def_boundaries_preserved() {
    ...
}

    #[test]
    fn byte_offset_to_line_conversion() {
    ...
}

    #[cfg(feature = "lang-rust")]
    #[test]
    fn line_numbers_are_correct_for_code_chunks() {
    ...
}
}
