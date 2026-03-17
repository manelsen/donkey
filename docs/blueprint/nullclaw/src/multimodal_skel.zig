//! Multimodal image processing — [IMAGE:] marker parsing, MIME detection,
//! base64 encoding, and ephemeral content_parts preparation for providers.
//!
//! Ported from ZeroClaw's `src/multimodal.rs`.
//! Images travel as `[IMAGE:path]` markers in content strings through the
//! entire pipeline. Conversion to `content_parts` happens ephemerally at
//! send time (arena-allocated), with no changes to session/agent signatures
//! or message history storage.

const std = @import("std");
const fs_compat = @import("fs_compat.zig");
const providers = @import("providers/root.zig");
const ChatMessage = providers.ChatMessage;
const ContentPart = providers.ContentPart;
const path_security = @import("tools/path_security.zig");

const log = std.log.scoped(.multimodal);

// ════════════════════════════════════════════════════════════════════════════
// Configuration
// ════════════════════════════════════════════════════════════════════════════

pub const MultimodalConfig = struct {
    /// Allow passing remote image URLs (`https://...`) through to providers.
    /// Disabled by default for secure-by-default behavior.
    /// Directories from which local image reads are allowed.
    /// If empty, all local file reads are rejected (only URLs pass through).
    /// When true, skip the allowed_dirs check entirely (yolo mode).
    /// File size and MIME validation still apply.

pub const default_config = MultimodalConfig{