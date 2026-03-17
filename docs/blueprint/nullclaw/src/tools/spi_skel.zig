const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const Tool = root.Tool;
const ToolResult = root.ToolResult;
const JsonObjectMap = root.JsonObjectMap;

/// SPI hardware tool for Linux SPI device interaction.
/// Supports listing SPI devices, full-duplex transfer, and read-only mode.
/// On non-Linux platforms, returns a platform-unsupported error for device operations.
pub const SpiTool = struct {

    fn executeTransfer(allocator: std.mem.Allocator, args: JsonObjectMap, read_only: bool) !ToolResult

    /// Linux-only SPI transfer via ioctl.
        if (comptime builtin.os.tag != .linux) {

        // ioctl constants for SPI
        const SPI_IOC_WR_MODE: u32 = 0x40016B01;
        const SPI_IOC_WR_MAX_SPEED_HZ: u32 = 0x40046B04;
        const SPI_IOC_WR_BITS_PER_WORD: u32 = 0x40016B03;
        // SPI_IOC_MESSAGE(1) = _IOW('k', 0, struct spi_ioc_transfer) for 1 transfer
        const SPI_IOC_MESSAGE_1: u32 = 0x40206B00;

        // Open SPI device
            const msg = try std.fmt.allocPrint(allocator, "Failed to open SPI device '{

        // Set SPI mode
        var mode_val: u8 = mode;

        // Set bits per word
        var bpw: u8 = bits_per_word;

        // Set speed
        var spd: u32 = speed_hz;

        // Prepare rx buffer
        var rx_buf: [256]u8 = undefined;
        const len = tx_data.len;

        // struct spi_ioc_transfer (packed, 32 bytes on 64-bit)



        // Format response as hex

    fn formatSpiResponse(allocator: std.mem.Allocator, rx_data: []const u8) !ToolResult

/// Parse space-separated hex bytes ("FF 0A 3B") into a byte buffer.
/// Returns the number of bytes parsed.
pub fn parseHexBytes(hex_str: []const u8, out: []u8) !usize

// ── Tests ───────────────────────────────────────────────────────────

test "spi tool name" {
    var st = SpiTool{

test "spi tool description not empty" {
    var st = SpiTool{

test "spi tool schema has action" {
    var st = SpiTool{

test "spi list action on non-linux" {
    var st = SpiTool{

test "spi transfer on non-linux returns error" {
    if (comptime builtin.os.tag == .linux) return;
    var st = SpiTool{

test "spi read on non-linux returns error" {
    if (comptime builtin.os.tag == .linux) return;
    var st = SpiTool{

test "spi missing action" {
    var st = SpiTool{

test "spi unknown action" {
    var st = SpiTool{

test "parseHexBytes basic" {
    var buf: [8]u8 = undefined;
    const len = try parseHexBytes("FF 0A", &buf);

test "parseHexBytes single byte" {
    var buf: [8]u8 = undefined;
    const len = try parseHexBytes("AB", &buf);

test "parseHexBytes multiple spaces" {
    var buf: [8]u8 = undefined;
    const len = try parseHexBytes("  01   02   03  ", &buf);

test "parseHexBytes lowercase" {
    var buf: [8]u8 = undefined;
    const len = try parseHexBytes("ff 0a 3b", &buf);

test "parseHexBytes invalid hex" {
    var buf: [8]u8 = undefined;
    const result = parseHexBytes("GG", &buf);

test "parseHexBytes empty" {
    var buf: [8]u8 = undefined;
    const len = try parseHexBytes("", &buf);

test "parseHexBytes three digit token fails" {
    var buf: [8]u8 = undefined;
    const result = parseHexBytes("FFF", &buf);

test "formatSpiResponse builds json" {
    const data = [_]u8{
