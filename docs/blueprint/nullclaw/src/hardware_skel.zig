const std = @import("std");
const builtin = @import("builtin");
const config = @import("config.zig");
const thread_stacks = @import("thread_stacks.zig");

// Hardware discovery -- USB device enumeration and introspection.
//
// Mirrors ZeroClaw's hardware module: registry of known USB VID/PID,
// device discovery, introspection, and wizard helpers.

// ── Board Registry ──────────────────────────────────────────────

/// Information about a known board.
pub const BoardInfo = struct {

/// Known USB VID/PID to board mappings.
/// VID 0x0483 = STMicroelectronics, 0x2341 = Arduino, 0x10c4 = Silicon Labs.

/// Look up a board by VID and PID.
pub fn lookupBoard(vid: u16, pid: u16) ?*const BoardInfo

/// Return all known board entries.
pub fn knownBoards() []const BoardInfo

// ── Discovered Device ───────────────────────────────────────────

/// A hardware device discovered during auto-scan.
pub const DiscoveredDevice = struct {

/// Auto-discover connected hardware devices.
/// On macOS: runs `system_profiler SPUSBDataType` and parses VID/PID.
/// On Linux: reads /sys/bus/usb/devices/ entries for idVendor/idProduct.
/// On other platforms: returns empty.
pub fn discoverHardware(allocator: std.mem.Allocator) ![]DiscoveredDevice

/// Parse a hex VID/PID value from a line like "  Vendor ID: 0x0483  (STMicroelectronics)"
/// or "  Product ID: 0x374b". Handles optional "0x" prefix and trailing text.
fn parseHexFromLine(line: []const u8, prefix: []const u8) ?u16

/// macOS discovery: spawn system_profiler and parse text output.
fn discoverMacOS(allocator: std.mem.Allocator) ![]DiscoveredDevice

/// Linux discovery: read /sys/bus/usb/devices/*/idVendor and idProduct.
fn discoverLinux(allocator: std.mem.Allocator) ![]DiscoveredDevice

/// Read a 4-digit hex value from a sysfs file like /sys/bus/usb/devices/<dev>/<attr>.
fn readSysfsHex(dir: std.fs.Dir, dev_name: []const u8, attr: []const u8) ?u16

/// Free a slice of DiscoveredDevice that was allocated by discoverHardware.
/// Safe to call with an empty comptime slice (returned on unsupported platforms).
pub fn freeDiscoveredDevices(allocator: std.mem.Allocator, devices: []DiscoveredDevice) void

// ── Wizard Helpers ──────────────────────────────────────────────

/// Return the recommended default wizard choice index based on discovered devices.
/// 0 = Native, 1 = Tethered/Serial, 2 = Debug Probe, 3 = Software Only
pub fn recommendedWizardDefault(devices: []const DiscoveredDevice) usize

/// Build a HardwareConfig from the wizard menu choice (0-3) and discovered devices.
pub fn configFromWizardChoice(choice: usize, devices: []const DiscoveredDevice) config.HardwareConfig

// ── Introspection ───────────────────────────────────────────────

/// Result of introspecting a device by path.
pub const IntrospectResult = struct {

/// Introspect a device by its serial path.
/// On macOS: runs system_profiler and matches device info.
/// On Linux: reads sysfs attributes for the device.
/// Returns basic VID/PID and board info if the device is recognized.
pub fn introspectDevice(allocator: std.mem.Allocator, path: []const u8) IntrospectResult

/// macOS introspection: parse system_profiler output to find VID/PID
/// for the first USB device, then look up in known_boards.
fn introspectMacOS(allocator: std.mem.Allocator, path: []const u8) IntrospectResult

/// Linux introspection: try to find the sysfs USB device for the given path,
/// then read idVendor/idProduct and look up in known_boards.
fn introspectLinux(path: []const u8) IntrospectResult

// ── USB Hotplug Monitoring ──────────────────────────────────────

/// A USB hotplug event emitted by the monitor.
/// Fields are slices into a temporary buffer — copy if you need to retain them.
pub const DeviceEvent = struct {
    /// Action string: "add", "remove", or "change".
    /// Subsystem/kind of the event (e.g. "usb", "tty").
    /// Composed device identifier: "VID:PID model" from udevadm properties,
    /// or the raw device path when properties are unavailable.
    /// Monotonic timestamp in seconds (from udevadm), or 0 if unavailable.

/// Callback invoked for each hotplug device event.
pub const DeviceEventCallback = *const fn (event: DeviceEvent, context: ?*anyopaque) void;

/// Real-time USB hotplug monitor that watches for device connect/disconnect events.
pub const HotplugMonitor = struct {

/// Start a hotplug monitor that calls `callback` on USB device events.
/// On Linux: spawns udevadm monitor --property and parses its output.
/// On macOS: logs that hotplug monitoring is not available and returns.
/// On other platforms: no-op (monitor.running stays false).
///
/// Caller must initialize `monitor` fields (allocator, callback/callback_ctx) before calling.
/// The monitor must remain at a stable address until stopHotplugMonitor() returns.
pub fn startHotplugMonitor(monitor: *HotplugMonitor) !void

/// Stop the hotplug monitor and wait for the thread to finish.
pub fn stopHotplugMonitor(monitor: *HotplugMonitor) void

/// Parse a udevadm monitor header line.
/// Expected format: "UDEV  [1234.567890] add      /devices/pci0000:00/... (usb)"
/// Returns a partial DeviceEvent with action, kind (subsystem), device_id (device path),
/// and timestamp. Returns null if the line cannot be parsed.
pub fn parseUdevLine(line: []const u8) ?DeviceEvent

/// Extract the action keyword from the beginning of the string.
/// Returns the slice "add", "remove", or "change", or null if unrecognized.
fn parseActionStr(rest: []const u8) ?[]const u8

/// Parse a udevadm property line of the form "KEY=value".
/// Returns the key and value slices, or null if the line is not a property.
pub fn parseUdevProperty(line: []const u8) ?struct

/// Build a device_id string from collected udevadm properties.
/// Format: "VID:PID model" if properties available, otherwise returns fallback.
        // No vendor info — use fallback
    const pid = product_id orelse "0000";

fn parseTimestampSecs(ts_str: []const u8) i64

/// Linux monitor: spawn `udevadm monitor --udev --subsystem-match=usb --property`
/// and parse header + property lines from its stdout.
fn runLinuxMonitor(monitor: *HotplugMonitor) void

// ── Tests ───────────────────────────────────────────────────────

test "lookupBoard finds nucleo-f401re" {
    const b = lookupBoard(0x0483, 0x374b);

test "lookupBoard finds nucleo-f411re" {
    const b = lookupBoard(0x0483, 0x3748);

test "lookupBoard finds arduino-uno" {
    const b = lookupBoard(0x2341, 0x0043);

test "lookupBoard finds arduino-mega" {
    const b = lookupBoard(0x2341, 0x0042);

test "lookupBoard finds cp2102" {
    const b = lookupBoard(0x10c4, 0xea60);

test "lookupBoard finds esp32" {
    const b = lookupBoard(0x1a86, 0x7523);

test "lookupBoard returns null for unknown VID/PID" {

test "lookupBoard returns null for partial match" {
    // Correct VID but wrong PID

test "knownBoards is not empty" {

test "knownBoards has at least 9 entries" {

test "all known boards have non-empty name" {

test "all known boards have architecture" {

test "discoverHardware does not error" {
    const devices = try discoverHardware(std.testing.allocator);
    // On CI or machines without USB devices this will be empty;
    // on a dev machine with known boards plugged in it may return results.
    // Either way, verify no error and clean up allocations.
    // Sanity: each discovered device has a non-empty name.

test "recommendedWizardDefault returns 3 for empty" {

test "recommendedWizardDefault returns 1 for non-empty" {
    const devices = [_]DiscoveredDevice{

test "configFromWizardChoice native" {
    const cfg = configFromWizardChoice(0, &.{

test "configFromWizardChoice serial" {
    const cfg = configFromWizardChoice(1, &devices);

test "configFromWizardChoice probe" {
    const cfg = configFromWizardChoice(2, &.{

test "configFromWizardChoice software only" {
    const cfg = configFromWizardChoice(3, &.{

test "configFromWizardChoice out of range defaults to software only" {
    const cfg = configFromWizardChoice(99, &.{

test "introspectDevice returns path" {
    const result = introspectDevice(std.testing.allocator, "/dev/ttyACM0");
    // VID/PID may or may not be populated depending on connected hardware.
    // Just verify the path is preserved.

test "introspectDevice has memory map note" {
    const result = introspectDevice(std.testing.allocator, "/dev/ttyUSB0");

// ── parseHexFromLine tests ──────────────────────────────────────

test "parseHexFromLine extracts VID with 0x prefix" {
    const vid = parseHexFromLine("          Vendor ID: 0x0483  (STMicroelectronics)", "Vendor ID:");

test "parseHexFromLine extracts PID with 0x prefix" {
    const pid = parseHexFromLine("          Product ID: 0x374b", "Product ID:");

test "parseHexFromLine handles uppercase hex" {
    const val = parseHexFromLine("  Vendor ID: 0xEA60", "Vendor ID:");

test "parseHexFromLine handles no 0x prefix" {
    const val = parseHexFromLine("  Vendor ID: 0483", "Vendor ID:");

test "parseHexFromLine returns null for missing prefix" {

test "parseHexFromLine returns null for empty value" {

test "parseHexFromLine handles 0X prefix" {
    const val = parseHexFromLine("  Vendor ID: 0X2341", "Vendor ID:");

test "parseHexFromLine with trailing parenthetical" {
    const vid = parseHexFromLine("          Vendor ID: 0x1a86  (QinHeng Electronics)", "Vendor ID:");

test "freeDiscoveredDevices with empty slice" {
    // Should not crash when called with an empty comptime slice.

// ── Hotplug Monitor Tests ──────────────────────────────────────

test "DeviceEvent struct creation" {

test "DeviceEvent all actions" {
    const added = DeviceEvent{

test "parseUdevLine parses add event" {
    const line = "UDEV  [1234.567890] add      /devices/pci0000:00/0000:00:14.0/usb1/1-1 (usb)";
    const event = parseUdevLine(line);

test "parseUdevLine parses remove event" {
    const line = "UDEV  [5678.123456] remove   /devices/pci0000:00/0000:00:14.0/usb1/1-1 (usb)";
    const event = parseUdevLine(line);

test "parseUdevLine parses change event" {
    const line = "UDEV  [9999.000000] change   /devices/pci0000:00/usb2/2-1 (tty)";
    const event = parseUdevLine(line);

test "parseUdevLine rejects KERNEL line" {
    const line = "KERNEL[1234.567890] add      /devices/pci0000:00/usb1/1-1 (usb)";

test "parseUdevLine rejects empty line" {

test "parseUdevLine rejects malformed line" {

test "parseUdevLine rejects unknown action" {
    const line = "UDEV  [1234.567890] bind     /devices/pci0000:00/usb1/1-1 (usb)";

test "parseUdevLine timestamp truncates to seconds" {
    const line = "UDEV  [100.500000000] add      /devices/test (usb)";
    const event = parseUdevLine(line);

test "parseUdevLine timestamp integer only" {
    const line = "UDEV  [42] add      /devices/test (usb)";
    const event = parseUdevLine(line);

test "parseUdevLine tty subsystem" {
    const line = "UDEV  [1000.000] add      /devices/pci0000:00/ttyUSB0 (tty)";
    const event = parseUdevLine(line);

// ── Property Parsing Tests ─────────────────────────────────────

test "parseUdevProperty parses key=value" {
    const prop = parseUdevProperty("ID_VENDOR_ID=0483");

test "parseUdevProperty parses ID_MODEL" {
    const prop = parseUdevProperty("ID_MODEL=Arduino_Uno");

test "parseUdevProperty parses empty value" {
    const prop = parseUdevProperty("ID_MODEL=");

test "parseUdevProperty rejects empty line" {

test "parseUdevProperty rejects line without equals" {

test "parseUdevProperty rejects lowercase key" {

test "parseUdevProperty rejects header line" {
    // UDEV header has spaces and brackets, not a valid property

// ── buildDeviceId Tests ────────────────────────────────────────

test "buildDeviceId with all properties" {
    var buf: [256]u8 = undefined;
    const id = buildDeviceId(&buf, "0483", "374b", "Nucleo_F401RE", "/dev/fallback");

test "buildDeviceId without model" {
    var buf: [256]u8 = undefined;
    const id = buildDeviceId(&buf, "1a86", "7523", null, "/dev/fallback");

test "buildDeviceId without vendor returns fallback" {
    var buf: [256]u8 = undefined;
    const id = buildDeviceId(&buf, null, null, null, "/devices/pci/usb1");

test "buildDeviceId without product uses 0000" {
    var buf: [256]u8 = undefined;
    const id = buildDeviceId(&buf, "0483", null, null, "/dev/fallback");

// ── DeviceEventCallback Tests ──────────────────────────────────

test "DeviceEventCallback with context" {
    const Ctx = struct {
    var ctx = Ctx{

test "DeviceEventCallback with null context" {
    const handler = struct {
    const event = DeviceEvent{

// ── HotplugMonitor Tests ───────────────────────────────────────

test "HotplugMonitor initial state" {

test "HotplugMonitor with callback" {
            fn cb(_: DeviceEvent, _: ?*anyopaque) void

test "startHotplugMonitor returns without error" {
            fn cb(_: DeviceEvent, _: ?*anyopaque) void
    // On macOS: logs and returns (no thread). On Linux: udevadm may fail but ok.

test "stopHotplugMonitor is safe to call twice" {
            fn cb(_: DeviceEvent, _: ?*anyopaque) void

test "startHotplugMonitor without callback" {
