const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const platform = @import("platform.zig");

// Peripherals -- hardware peripheral management (STM32, RPi GPIO, Arduino, etc).
//
// Mirrors ZeroClaw's peripherals module: the Peripheral trait/interface,
// board listing, serial/GPIO/flash backends, capabilities, and tool creation.

// ── Peripheral Interface ────────────────────────────────────────

/// Peripheral capabilities reported by a connected device.
pub const PeripheralCapabilities = struct {

/// A hardware peripheral that exposes capabilities as tools.
/// Implement this for boards like Nucleo-F401RE (serial), RPi GPIO (native), etc.
pub const Peripheral = struct {

// ── Allowed Serial Paths (security) ─────────────────────────────


pub fn isSerialPathAllowed(path: []const u8) bool

// ── SerialPeripheral ────────────────────────────────────────────

/// Serial peripheral for STM32, Arduino, etc. over USB CDC.
/// Protocol: newline-delimited JSON.
pub const SerialPeripheral = struct {

// ── ArduinoPeripheral ───────────────────────────────────────────

/// Arduino peripheral: detect boards via serial, upload sketches via arduino-cli.
pub const ArduinoPeripheral = struct {

// ── RpiGpioPeripheral ───────────────────────────────────────────

/// Raspberry Pi GPIO peripheral using sysfs interface.
/// Uses /sys/class/gpio/export, direction, value for pin access.
pub const RpiGpioPeripheral = struct {

// ── NucleoFlash ─────────────────────────────────────────────────

/// STM32 Nucleo board flash utility via probe-rs.
pub const NucleoFlash = struct {

// ── GPIO Tool Helpers ───────────────────────────────────────────

/// Result of a GPIO read operation.
pub const GpioReadResult = struct {

/// Result of a GPIO write operation.
pub const GpioWriteResult = struct {

/// Read a GPIO pin via a peripheral. Returns "HIGH" or "LOW".
pub fn gpioRead(p: Peripheral, pin: u32) Peripheral.PeripheralError!GpioReadResult

/// Write a GPIO pin via a peripheral.
pub fn gpioWrite(p: Peripheral, pin: u32, high: bool) Peripheral.PeripheralError!GpioWriteResult

// ── Board Listing ───────────────────────────────────────────────

/// Supported board types that can be configured as peripherals.
pub const SupportedBoard = enum {

/// List configured boards from config. Returns empty if peripherals disabled.
pub fn listConfiguredBoards(peripherals_config: config.PeripheralsConfig) []const u8

/// Check if a board name is recognized.
pub fn isKnownBoard(board_name: []const u8) bool

/// Validate a board transport string.
pub fn isValidTransport(transport: []const u8) bool

/// Validate a baud rate.
pub fn isValidBaudRate(baud: u32) bool

/// Create peripheral tool count from config.
/// Returns 0 when peripherals are disabled (no hardware feature linked).
pub fn createPeripheralToolCount(peripherals_config: config.PeripheralsConfig) usize

// ── Tests ───────────────────────────────────────────────────────

test "SupportedBoard.fromString finds nucleo-f401re" {
    const board = SupportedBoard.fromString("nucleo-f401re");

test "SupportedBoard.fromString finds nucleo-f411re" {
    const board = SupportedBoard.fromString("nucleo-f411re");

test "SupportedBoard.fromString finds arduino-uno" {
    const board = SupportedBoard.fromString("arduino-uno");

test "SupportedBoard.fromString finds arduino-uno-q" {
    const board = SupportedBoard.fromString("arduino-uno-q");

test "SupportedBoard.fromString finds uno-q alias" {
    const board = SupportedBoard.fromString("uno-q");

test "SupportedBoard.fromString finds esp32" {
    const board = SupportedBoard.fromString("esp32");

test "SupportedBoard.fromString finds rpi-gpio" {
    const board = SupportedBoard.fromString("rpi-gpio");

test "SupportedBoard.fromString finds raspberry-pi alias" {
    const board = SupportedBoard.fromString("raspberry-pi");

test "SupportedBoard.fromString returns null for unknown" {

test "SupportedBoard.displayName" {

test "SupportedBoard.defaultTransport" {

test "SupportedBoard.all returns all boards" {

test "isKnownBoard recognizes valid boards" {

test "isKnownBoard rejects unknown" {

test "isValidTransport accepts valid transports" {

test "isValidTransport rejects unknown" {

test "isValidBaudRate accepts common rates" {

test "isValidBaudRate rejects uncommon rates" {

test "listConfiguredBoards disabled" {
    const cfg = config.PeripheralsConfig{

test "listConfiguredBoards enabled" {
    const cfg = config.PeripheralsConfig{

test "createPeripheralToolCount disabled returns 0" {
    const cfg = config.PeripheralsConfig{

test "createPeripheralToolCount enabled returns 2" {
    const cfg = config.PeripheralsConfig{

test "PeripheralBoardConfig defaults" {
    const board_cfg = config.PeripheralBoardConfig{

// ── Peripheral vtable tests ─────────────────────────────────────

test "SerialPeripheral create rejects disallowed path" {
    const result = SerialPeripheral.create("/etc/passwd", "test", 115200);

test "SerialPeripheral vtable dispatches correctly" {
    const p = serial.peripheral();
    const caps = p.getCapabilities();

test "SerialPeripheral read fails when not connected" {
    const p = serial.peripheral();

test "ArduinoPeripheral vtable works" {
    var arduino = ArduinoPeripheral.create(std.testing.allocator, "/dev/cu.usbmodem0001", 115200);
    const p = arduino.peripheral();
    const caps = p.getCapabilities();

test "ArduinoPeripheral flash fails when not connected" {
    var arduino = ArduinoPeripheral.create(std.testing.allocator, "/dev/cu.usbmodem0001", 115200);
    const p = arduino.peripheral();

test "RpiGpioPeripheral vtable works" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();
    const caps = p.getCapabilities();

test "RpiGpioPeripheral read fails when not connected" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();

test "RpiGpioPeripheral invalid address" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();

test "RpiGpioPeripheral flash not supported" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();

test "RpiGpioPeripheral.gpioStateString" {

test "NucleoFlash vtable works" {
    var nucleo = NucleoFlash.createF401(std.testing.allocator);
    const p = nucleo.peripheral();
    const caps = p.getCapabilities();

test "NucleoFlash F411 creation" {
    const nucleo = NucleoFlash.createF411(std.testing.allocator);

test "NucleoFlash read fails when not connected" {
    var nucleo = NucleoFlash.createF401(std.testing.allocator);
    const p = nucleo.peripheral();

test "NucleoFlash flash with empty path fails" {
    var nucleo = NucleoFlash.createF401(std.testing.allocator);
    const p = nucleo.peripheral();

// ── GPIO tool helper tests ──────────────────────────────────────

test "gpioRead returns result with state" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();
    if (comptime builtin.os.tag == .linux) {
        // Only run on real RPi hardware — requires NULLCLAW_GPIO_TEST=1
        const result = try gpioRead(p, 17);

test "gpioWrite returns success" {
    var rpi = RpiGpioPeripheral.create();
    const p = rpi.peripheral();
    if (comptime builtin.os.tag == .linux) {
        // Only run on real RPi hardware — requires NULLCLAW_GPIO_TEST=1
        const result = try gpioWrite(p, 17, true);

// ── Serial path security tests ──────────────────────────────────

test "isSerialPathAllowed accepts valid paths" {

test "isSerialPathAllowed rejects invalid paths" {

// ── Board capabilities tests ────────────────────────────────────

test "SupportedBoard.defaultCapabilities for nucleo" {
    const caps = SupportedBoard.nucleo_f401re.defaultCapabilities();

test "SupportedBoard.defaultCapabilities for arduino" {
    const caps = SupportedBoard.arduino_uno.defaultCapabilities();

test "SupportedBoard.defaultCapabilities for rpi" {
    const caps = SupportedBoard.rpi_gpio.defaultCapabilities();

test "SupportedBoard.defaultCapabilities for esp32" {
    const caps = SupportedBoard.esp32.defaultCapabilities();

test "PeripheralCapabilities defaults" {
    const caps = PeripheralCapabilities{
