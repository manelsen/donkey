const std = @import("std");
const Allocator = std.mem.Allocator;
const audit_log = std.log.scoped(.audit);

/// Audit event types
pub const AuditEventType = enum {

/// Actor information (who performed the action)
pub const Actor = struct {

/// Action information (what was done)
pub const Action = struct {

/// Execution result
pub const ExecutionResult = struct {

/// Security context
pub const SecurityContext = struct {

/// Complete audit event
pub const AuditEvent = struct {
    /// Timestamp in seconds since epoch (UTC)
    /// Unique event identifier (counter-based for simplicity)
    /// Global counter for unique event IDs
    /// Create a new audit event with current timestamp and unique ID