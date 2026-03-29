# Contributing to Donkey
Guide for contributors

## Getting Started

### Prerequisites

- Nim 2.0+
- Git
- Basic understanding of hexagonal architecture

### Setup

```bash
# Clone repository
git clone https://github.com/manelsen/donkey.git
cd donkey

# Install dependencies
nimble install

# Build
nim c src/donkey
```

## Development

### Building

```bash
# Standard build
nim c src/donkey

# With database support
nim c -d:withSqlite src/donkey
nim c -d:withPostgres src/donkey

# Production build
nim c -d:release --mm:orc --warningAsError:on src/donkey
```

### Testing

```bash
# Run all tests
nimble test

# Run specific test
nim c -r tests/core/t_my_module.nim

# With coverage
nimble test --coverage
```

## Project Structure

```
src/donkey/
├── core/           # Pure domain logic
├── ports/          # Interface definitions
├── adapters/       # Implementation
├── domain/         # Business types
├── config/         # Configuration
├── app/            # Application layer
└── infra/          # Infrastructure
```

## Code Style

### Naming

| Element | Convention | Example |
|---------|-----------|---------|
| Modules | snake_case | `session_ingress.nim` |
| Types | PascalCase | `SessionId`, `ChannelKind` |
| Functions | snake_case | `handleMessage` |
| Constants | SCREAMING_SNAKE | `MAX_RETRIES` |
| Variables | snake_case | `session_id` |

### Import Order

1. Standard library
2. External packages
3. Internal modules

```nim
import std/[strutils, sequtils]
import chronos, parsetoml
import ../core/types
import ../domain/message
```

## Architecture

### Hexagonal Architecture

```
ports/     ← Interfaces (no dependencies on adapters)
    ↓
core/      ← Pure logic (no external dependencies)
    ↓
adapters/  ← Implementations
```

### Rules

- `core/` must NOT import `adapters/`
- `ports/` must NOT import `adapters/`
- `domain/` must NOT import external packages

## Pull Requests

### Process

1. Fork repository
2. Create feature branch: `us/<id>-<description>`
3. Make changes with tests
4. Run quality gates
5. Submit PR

### Quality Gates

All PRs must pass:

```bash
# Compilation
nim c --mm:orc src/donkey

# Style check
nim c --styleCheck:error src/donkey

# Tests
nimble test

# Boundary check
bash scripts/check_boundaries.sh
```

## Testing

### Test Structure

Tests mirror source structure:

```
tests/
├── core/           # Core tests
├── ports/          # Port tests
├── adapters/       # Adapter tests
└── domain/         # Domain tests
```

### Writing Tests

```nim
import std/unittest
import donkey/core/my_module

suite "MyModule":
  test "does something":
    let result = myFunction()
    check result == expected
```

## Documentation

### Documentation Style

- Use Markdown
- Include code examples
- Document public APIs

### Doc Comments

```nim
func myFunction*(arg: string): int
  ## Does something with the argument.
  ##
  ## .. code-block:: nim
  ##
  ##   let result = myFunction("hello")
  ##
  ## Returns the length of the argument.
  discard
```

## Issues

### Bug Reports

Include:
- Environment (OS, Nim version)
- Steps to reproduce
- Expected vs actual behavior
- Minimal reproduction case

### Feature Requests

Include:
- Problem to solve
- Proposed solution
- Alternative solutions considered

## Code of Conduct

- Be respectful
- Be constructive
- Focus on the code

## License

By contributing, you agree that your contributions will be licensed under the same license as Donkey.
