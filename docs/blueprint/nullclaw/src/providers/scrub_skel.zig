const std = @import("std");
const builtin = @import("builtin");

const DEFAULT_MAX_API_ERROR_CHARS: usize = 200;
const MIN_MAX_API_ERROR_CHARS: usize = 200;
const MAX_MAX_API_ERROR_CHARS: usize = 10_000;

const NO_API_ERROR_LIMIT_OVERRIDE: usize = 0;

pub const ApiErrorLimitOverrideError = error{