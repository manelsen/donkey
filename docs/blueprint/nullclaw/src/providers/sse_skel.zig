const std = @import("std");
const builtin = @import("builtin");
const root = @import("root.zig");
const fs_compat = @import("../fs_compat.zig");
const http_util = @import("../http_util.zig");
const platform = @import("../platform.zig");
const error_classify = @import("error_classify.zig");
const verbose = @import("../verbose.zig");
const log = std.log.scoped(.provider_sse);

var curl_fail_fast_arg_mutex: std.Thread.Mutex = .{