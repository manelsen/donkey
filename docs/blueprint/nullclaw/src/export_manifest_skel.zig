/// Export manifest JSON for nullhub integration.
///
/// Generates the manifest from the same data structures used by the
/// interactive wizard (onboard.zig) and channel catalog, ensuring a
/// single source of truth.
const std = @import("std");
const onboard = @import("onboard.zig");
const channel_catalog = @import("channel_catalog.zig");
const version = @import("version.zig");

pub fn run() !void

test "export_manifest produces valid structure" {
    // Verify the data sources are accessible and have expected counts

    // Verify first provider

    // Verify memory backends start with hybrid
