# Outbound Presentation Architecture

## Purpose

Donkey treats outbound UI as a core concern, not an adapter-local trick.
The goal is to let the core describe **what surface is being shown** while
ports and adapters decide **how that surface is projected** on a given channel.

This keeps channel names and one-off UI state out of orchestration logic.

## Ownership Boundaries

### Core owns

- Presentation surface vocabulary
- Replaceable vs streaming semantics
- Shared fallback copy for non-editable surfaces
- Channel capability policy
- Mutable presentation state keys and lifecycle

These live under [src/donkey/core/outbound/outbound.nim](/home/micelio/git/donkey/src/donkey/core/outbound/outbound.nim).

Key types:

- `PresentationSurface`
- `PresentationMessage`
- `PresentationState`
- `PresentationCapabilities`

Key helpers:

- `buildReplacementSurface`
- `buildStreamingSurface`
- `presentationCapabilities`
- `replacementSlotFor`
- `interactiveSelectionFallbackText`

### Application/runtime owns

- Routing outbound messages to the correct channel port
- Reusing or editing previously sent channel messages
- Storing channel message ids inside the shared presentation state

This lives in [src/donkey/app/outbound_runtime.nim](/home/micelio/git/donkey/src/donkey/app/outbound_runtime.nim).

Representative path:

1. Core or orchestrator emits an `OutboundMessage` carrying presentation intent.
2. `routeOutbound(...)` consults `PresentationState`.
3. The runtime decides whether to send, edit, create stream output, or suppress partial output.
4. The channel port performs the concrete send/edit API call.

### Adapters own

- API-specific send/edit mechanics
- Channel-specific payload translation
- Capability projection already decided upstream

Adapters must not invent shared fallback wording or slot semantics.

## Editable Surfaces

Replaceable UI such as `bootstrap`, `menu`, `config`, `models`, `think`, and `help`
uses logical slots rather than adapter-local message tables.

The slot is declared once in the message intent and normalized through
`replacementSlotFor(channel, slot)` in the core boundary.

If a channel supports editable replacement:

- the slot is kept
- the runtime edits the previous message when possible

If a channel does not support editable replacement:

- the slot is stripped by policy
- the surface falls back to plain outbound behavior

## Non-Editable Fallbacks

Shared fallback copy belongs to the presentation boundary.

Current example:

- `interactiveSelectionFallbackText()` returns the canonical message used when
  the user types while the system is waiting for a button choice

This prevents each runtime from inventing slightly different wording for the
same conceptual surface.

The onboarding core consumes that helper in
[src/donkey/core/onboarding/onboarding.nim](/home/micelio/git/donkey/src/donkey/core/onboarding/onboarding.nim).

## Status And Streaming

Status and streaming are not separate ad hoc systems anymore.

`PresentationState` now tracks:

- `replacementMsgIds`
- `streamMsgIds`
- `statusMsgIds`

That means:

- reusable menus
- streamed partial/final replies
- fallback status anchors

all share the same state boundary and keying model.

Relevant code paths:

- [src/donkey/core/outbound/outbound.nim](/home/micelio/git/donkey/src/donkey/core/outbound/outbound.nim)
- [src/donkey/app/outbound_runtime.nim](/home/micelio/git/donkey/src/donkey/app/outbound_runtime.nim)
- [src/donkey.nim](/home/micelio/git/donkey/src/donkey.nim)

## State Ownership

`PresentationState` is owned by the daemon runtime and passed through the
application boundary. Adapters consume it through runtime helpers, but do not
own the schema.

This is the current ownership chain:

1. daemon initializes `PresentationState`
2. orchestrator emits presentation intent
3. outbound runtime updates bindings
4. adapters only execute channel operations

## Rules For Future UI Work

- Add new shared UI semantics in `core/outbound` first.
- Prefer logical slots over adapter-local message id tables.
- Put shared fallback wording in the presentation boundary, not in adapters.
- Ask capability questions through `presentationCapabilities`, not by naming channels.
- Extend `PresentationState` only when the surface truly belongs to outbound presentation.

## Current Limits

- Projection still happens in the outbound runtime, not in a separate presentation port.
- Some channel-specific rendering remains adapter-local by necessity.
- Streaming UX still shares existing adapter mechanics; only ownership and state were centralized.
