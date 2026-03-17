# Nullclaw Skeletons

This directory contains API skeletons extracted from the **nullclaw** project Zig codebase.

## What are Skeletons?

Skeletons are stripped-down versions of Zig source files that contain only:
- **Function signatures** (parameter types, return types)
- **Type definitions** (structs, enums, unions, error sets)
- **Import statements** and module structure
- **Public API declarations** (pub fn, pub const, pub var)
- **Comments and docstrings** (/// documentation)
- **Test blocks** (test declarations)

What is **removed**:
- Function body implementations
- Private helper functions
- Inline logic and computations
- Detailed error handling code

## Purpose

These skeletons serve as:
1. **API Documentation** - Quick reference for understanding the public interface of modules
2. **Architecture Overview** - See the structure and relationships between components
3. **Learning Resource** - Study the codebase organization without implementation details
4. **Integration Guide** - Understand what functions/types are available for external use

## Directory Structure

The skeleton files maintain the same directory structure as the original nullclaw project:

```
docs/blueprint/nullclaw/
├── src/
│   ├── main_skel.zig           # Entry point
│   ├── agent_skel.zig          # Agent orchestration
│   ├── config_skel.zig         # Configuration types (226K → skeleton)
│   ├── channels/               # Communication channels (25+ implementations)
│   ├── providers/              # LLM providers (OpenAI, Anthropic, etc.)
│   ├── tools/                  # Built-in tools (shell, file, browser, etc.)
│   ├── security/               # Security and sandboxing
│   ├── memory/                 # Memory and vector storage
│   └── ...                     # Other modules
└── vendor/                     # Third-party dependencies
```

## Priority Modules

Key modules that define the core architecture:

| Module | Description | Size |
|--------|-------------|------|
| `src/main.zig` | CLI entry point, command parsing | 93 lines (skeleton) |
| `src/agent.zig` | Agent orchestration and context | 13 lines (skeleton) |
| `src/config.zig` | Complete configuration types | 100+ lines (skeleton) |
| `src/channels/` | Communication adapters (Discord, Slack, etc.) | 25+ files |
| `src/providers/` | LLM provider implementations | 12+ files |
| `src/tools/` | Built-in tool implementations | 40+ files |
| `src/security/` | Sandbox and security policies | 10+ files |

## File Naming Convention

Skeleton files are named with the `_skel.zig` suffix:
- Original: `src/main.zig`
- Skeleton: `src/main_skel.zig`

## Usage Examples

### Viewing the public API of a module

```bash
# View the agent module's public interface
cat docs/blueprint/nullclaw/src/agent_skel.zig

# View all available channels
ls docs/blueprint/nullclaw/src/channels/

# See what tools are available
ls docs/blueprint/nullclaw/src/tools/
```

### Understanding function signatures

```zig
// From src/tools/shell_skel.zig
pub const ShellTool = struct {
    /// Execute a shell command with workspace scoping
    pub fn execute(
        self: *ShellTool,
        allocator: std.mem.Allocator,
        command: []const u8,
        env_vars: ?[]const []const u8,
        timeout_ns: u64,
    ) !ToolResult
```

### Comparing original vs skeleton

```bash
# See the implementation details
less /home/micelio/git/donkey/inspiration/nullclaw/src/tools/shell.zig

# See just the API
less docs/blueprint/nullclaw/src/tools/shell_skel.zig
```

## Statistics

- **Total Zig files processed**: 249
- **Skeleton files generated**: 249
- **Priority modules**: 100+ files
- **Total lines removed**: ~200,000+ (implementation code)

## Key Insights from Skeletons

### Architecture Patterns

1. **Provider Pattern** - LLM providers implement a common `Provider` interface
2. **Channel Pattern** - Communication channels use adapter pattern
3. **Tool Pattern** - Extensible tool system with registration
4. **Memory Pattern** - Pluggable memory engines with vector search

### Module Relationships

```
main.zig
  └─> agent.zig (orchestration)
        ├─> providers/ (LLM backends)
        ├─> channels/ (communication)
        ├─> tools/ (capabilities)
        └─> memory/ (persistence)
```

## Notes

- The `config.zig` skeleton captures all type definitions but not validation logic
- Test blocks are preserved to show expected behavior
- Private functions (without `pub`) are omitted unless part of struct definitions
- Complex inline expressions in type definitions are preserved where relevant

## Original Project

The nullclaw project is located at:
```
/home/micelio/git/donkey/inspiration/nullclaw/
```

## Generation

Skeletons were generated using a Python script that:
1. Parses Zig source files
2. Extracts function/type signatures using regex patterns
3. Preserves structural elements (imports, comments, tests)
4. Removes implementation bodies while keeping declarations
5. Maintains directory structure

See `extract_skeletons.py` in the parent directory for the generation logic.
