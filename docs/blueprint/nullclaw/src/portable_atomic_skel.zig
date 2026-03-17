//! Platform-portable atomic value.
//!
//! On targets where the requested integer width fits the native word size,
//! this is a zero-cost alias for `std.atomic.Value(T)`.
//!
//! On 32-bit targets (e.g. ARM32) where `T` exceeds the native word width,
//! falls back to a mutex-protected wrapper with an API-compatible surface
//! (init / load / store / fetchAdd).

const std = @import("std");

pub fn Atomic(comptime T: type) type

fn MutexAtomic(comptime T: type) type

// ── Tests ───────────────────────────────────────────────────────────

test "Atomic i64 init load store" {
    var a = Atomic(i64).init(42);

test "Atomic u64 fetchAdd" {
    var a = Atomic(u64).init(0);
    const old = a.fetchAdd(5, .monotonic);

test "Atomic bool passthrough" {
    // bool fits in usize, so this must be std.atomic.Value(bool)
    var a = Atomic(bool).init(false);
