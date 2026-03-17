//! Circuit breaker — pure state machine for embedding provider failure protection.
//!
//! States: closed (normal), open (tripped), half_open (cooldown expired, probe).
//! No I/O, no allocator, no external dependencies.

const std = @import("std");

pub const State = enum { closed, open, half_open };
    /// Guards half_open to allow exactly one probe request before requiring
    /// recordSuccess/recordFailure.