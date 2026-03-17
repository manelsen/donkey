//! Service management — launchd (macOS), systemd (Linux), and SCM (Windows).
//!
//! Mirrors ZeroClaw's service module: install, start, stop, restart, status, uninstall.
//! Uses child process execution to interact with launchctl / systemctl / sc.exe.

const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");
const Config = @import("config.zig").Config;
const daemon = @import("daemon.zig");
const http_util = @import("http_util.zig");
const providers = @import("providers/root.zig");

const SERVICE_LABEL = "com.nullclaw.daemon";
const WINDOWS_SERVICE_NAME = "nullclaw";
const WINDOWS_SERVICE_DISPLAY_NAME = "nullclaw gateway runtime";
pub const WINDOWS_SERVICE_GATEWAY_ARG = "__windows-service-gateway";

const windows = std.os.windows;
const WINDOWS_SERVICE_NAME_W = std.unicode.utf8ToUtf16LeStringLiteral(WINDOWS_SERVICE_NAME);

const WindowsServiceStatusHandle = ?*opaque{