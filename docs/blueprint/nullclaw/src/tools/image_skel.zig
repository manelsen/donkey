const std = @import("std");
const fs_compat = @import("../fs_compat.zig");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// Maximum image file size (5MB).
const MAX_IMAGE_BYTES: u64 = 5_242_880;

/// Tool to read image metadata (format, dimensions, size).
pub const ImageInfoTool = struct {

/// Detect image format from magic bytes.
pub fn detectFormat(bytes: []const u8) []const u8

/// Extract image dimensions from header bytes.
pub fn extractDimensions(bytes: []const u8, format: []const u8) ?[2]u32

/// Parse JPEG SOF markers to extract dimensions.
fn jpegDimensions(bytes: []const u8) ?[2]u32

// ── Tests ───────────────────────────────────────────────────────────

test "image_info tool name" {
    var it = ImageInfoTool{

test "image_info schema has path" {
    var it = ImageInfoTool{

// ── Format detection tests ──────────────────────────────────────────

test "detect PNG" {
    const bytes = &[_]u8{

test "detect JPEG" {
    const bytes = &[_]u8{

test "detect GIF" {
    const bytes = "GIF89a";

test "detect BMP" {
    const bytes = &[_]u8{

test "detect WEBP" {
    const bytes = &[_]u8{

test "detect unknown short" {

test "detect unknown garbage" {

// ── Dimension extraction tests ──────────────────────────────────────

test "PNG dimensions" {
    const dims = extractDimensions(&bytes, "png");

test "GIF dimensions" {
    const dims = extractDimensions(&bytes, "gif");

test "BMP dimensions" {
    var bytes = [_]u8{

test "JPEG dimensions" {
    const dims = extractDimensions(&bytes, "jpeg");

test "JPEG malformed zero-length segment" {
    const dims = extractDimensions(&bytes, "jpeg");

test "unknown format no dimensions" {

// ── Additional format detection tests ───────────────────────────

test "detect empty bytes" {

test "detect single byte" {

test "detect three bytes" {

test "detect RIFF without WEBP" {
    const bytes = &[_]u8{

test "detect JPEG with different APP marker" {
    // JPEG with APP1 (EXIF) marker instead of APP0
    const bytes = &[_]u8{

test "detect GIF87a variant" {
    const bytes = "GIF87a";

test "detect TIFF not supported returns unknown" {
    // TIFF little-endian
    const bytes = &[_]u8{

// ── Additional dimension extraction tests ───────────────────────

test "PNG dimensions insufficient bytes" {

test "GIF dimensions insufficient bytes" {
    const bytes = [_]u8{

test "BMP dimensions insufficient bytes" {
    var bytes = [_]u8{

test "BMP negative height" {
    // BMP with negative height (top-down bitmap)
    var bytes = [_]u8{

test "WEBP no dimensions" {
    // WEBP format detection works but dimension extraction not implemented
    const bytes = &[_]u8{

test "JPEG no SOF marker returns null" {
    // JPEG with only APP0 segment and no SOF marker
    const dims = extractDimensions(&bytes, "jpeg");

test "JPEG non-FF byte returns null" {
    // After SOI, encounter non-marker byte
    const dims = extractDimensions(&bytes, "jpeg");

test "image_info schema has include_base64" {
    var it = ImageInfoTool{

test "image_info description mentions metadata" {
    var it = ImageInfoTool{
