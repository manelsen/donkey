//! Image processing operations for LLM-ready media.
//!
//! Provides utilities for resizing and optimizing images before sending to LLMs.
//! Handles dimension limits, file size constraints, and format conversion.

use std::io::Cursor;

use {
    crate::{Error, Result},
    image::{DynamicImage, GenericImageView, ImageFormat, ImageReader},
};

/// Default maximum dimension (width or height) for images.
/// Claude API allows 8000px for single images, 2000px for multi-image requests.
/// We use 1568px as a conservative default that works well with both providers.
pub const DEFAULT_MAX_DIMENSION: u32 = 1568;

/// Maximum file size for Anthropic API (5MB).
pub const MAX_FILE_SIZE_BYTES: usize = 5 * 1024 * 1024;

/// JPEG quality for resized images (0-100).
pub const DEFAULT_JPEG_QUALITY: u8 = 85;

/// Image metadata.
#[derive(Debug, Clone)]
pub struct ImageMetadata {
    ...
}

/// Result of image optimization.
#[derive(Debug)]
pub struct OptimizedImage {
    ...
}

/// Get metadata about an image without fully decoding it.
pub fn get_image_metadata(data: &[u8]) -> Result<ImageMetadata> {
    ...
}

/// Check if an image needs resizing based on dimensions or file size.
pub fn needs_optimization(data: &[u8], max_dimension: u32) -> Result<bool> {
    ...
}

/// Resize image to fit within max dimensions while preserving aspect ratio.
/// Returns the original data if no resizing is needed.
pub fn resize_image(data: &[u8], max_width: u32, max_height: u32) -> Result<Vec<u8>> {
    ...
}

/// Optimize an image for LLM consumption.
///
/// This function:
/// 1. Checks if the image exceeds dimension or file size limits
/// 2. Resizes if needed, preserving aspect ratio
/// 3. Converts to JPEG for efficiency (unless PNG with transparency is needed)
/// 4. Ensures the output is under the API size limit
///
/// # Arguments
/// * `data` - Raw image bytes
/// * `max_dimension` - Maximum width or height (default: 1568)
///
/// # Returns
/// * `OptimizedImage` with the processed data and metadata
pub fn optimize_for_llm(data: &[u8], max_dimension: Option<u32>) -> Result<OptimizedImage> {
    ...
}

/// Resize image to fit within max dimension, preserving aspect ratio.
fn resize_to_fit(img: &DynamicImage, max_dimension: u32) -> (u32, u32, DynamicImage) {
    ...
}

/// Encode image as JPEG with specified quality.
fn encode_jpeg_with_quality(img: &DynamicImage, quality: u8) -> Result<(Vec<u8>, &'static str)> {
    ...
}

/// Progressively reduce quality until image fits within size limit.
fn reduce_size_to_fit(img: &DynamicImage, max_bytes: usize) -> Result<Vec<u8>> {
    ...
}

/// Convert ImageFormat to MIME type string.
fn format_to_media_type(format: Option<ImageFormat>) -> &'static str {
    ...
}

#[allow(clippy::unwrap_used, clippy::expect_used)]
#[cfg(test)]
mod tests {

    #[test]
    fn test_needs_optimization_small_image() {
    ...
}

    #[test]
    fn test_resize_no_change_needed() {
    ...
}

    #[test]
    fn test_optimize_for_llm_small_image() {
    ...
}

    #[test]
    fn test_format_to_media_type() {
    ...
}
}
