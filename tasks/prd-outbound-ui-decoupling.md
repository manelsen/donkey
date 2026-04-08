[PRD]
# PRD: Outbound UI Decoupling and Presentation Surface Refactor

## Overview

The Donkey codebase has already started decoupling ephemeral channel UI from adapter-specific message IDs by introducing `replacementSlot` in outbound flows and named UI slots in Telegram and Discord runtimes. The next phase should complete that direction deliberately.

This refactor will move the system from ad hoc per-channel UI state and adapter-owned presentation choices toward a core-owned presentation surface. The immediate goal is to unify ephemeral UI behavior across channels, including editable menus and interactive surfaces, while also bringing status and streaming-related UI into scope so the presentation model stops fragmenting.

The end state should make the core describe *what* UI surface is being shown or updated, while ports/adapters decide *how* that maps to Telegram, Discord, and channels with weaker capabilities.

## Goals

- Centralize UI surface ownership closer to the core instead of leaving it scattered across adapters.
- Replace remaining adapter-local keyboard/message tracking with a shared presentation abstraction.
- Extend the abstraction beyond menus to include status and streaming-related ephemeral UI.
- Make channel capability differences explicit and reusable instead of hardcoded in orchestration logic.
- Preserve current user behavior while reducing state duplication and accidental cross-menu interference.
- Keep changes shippable in small stories with clear verification boundaries.

## Quality Gates

These commands must pass for every user story:
- `nim c --mm:orc src/donkey.nim`
- `nim c --mm:orc -r tests/adapters/channel/t_telegram_runtime.nim`
- `nim c --mm:orc -r tests/channel/t_discord.nim`
- `nim c --mm:orc -r tests/app/t_outbound_runtime.nim`
- `nim c --mm:orc -r tests/app/t_orchestrator.nim`

For stories that touch broader routing or common runtime behavior, also run:
- `nim c --mm:orc -r tests/adapters/channel/t_common_runtime.nim`

## User Stories

### US-001: Define a core presentation surface model
**Description:** As a maintainer, I want a canonical presentation surface model in the core so that channels stop inventing their own UI-state conventions.

**Acceptance Criteria:**
- [ ] A core-owned type or set of types defines reusable presentation concepts such as replaceable surfaces, slots, and update semantics.
- [ ] The model does not reference Telegram-, Discord-, or adapter-specific API names.
- [ ] Existing outbound flows can map to the new model without changing visible behavior.
- [ ] There is test coverage proving the model can represent reusable/editable UI independently of channel-specific mechanics.

### US-002: Introduce a presentation state runtime/port boundary
**Description:** As a maintainer, I want presentation state managed through a dedicated boundary so that adapters no longer own mutable UI slot bookkeeping directly.

**Acceptance Criteria:**
- [ ] A runtime or port is introduced to manage presentation state such as slot-to-message bindings.
- [ ] Telegram and Discord no longer implement their own slot keying helpers locally.
- [ ] The new boundary is reusable from multiple channel runtimes.
- [ ] Existing bootstrap replacement behavior continues to work unchanged.

### US-003: Migrate menu/config/model/think/help to the shared presentation runtime
**Description:** As a user, I want interactive menus to behave consistently across channels so that opening one surface does not accidentally stomp another.

**Acceptance Criteria:**
- [ ] `menu`, `config`, `models`, `think`, and `help` use the shared presentation runtime instead of adapter-local state tables.
- [ ] Telegram and Discord each preserve their current UX semantics where supported.
- [ ] Separate UI surfaces keep independent state and do not overwrite each other accidentally.
- [ ] Regression tests cover at least one multi-surface scenario per supported interactive channel.

### US-004: Bring status and streaming UI into the same presentation model
**Description:** As a maintainer, I want status and streaming surfaces modeled in the same system so that ephemeral presentation behavior is not split across unrelated mechanisms.

**Acceptance Criteria:**
- [ ] The design explicitly covers status and streaming-related UI updates, not just static menus.
- [ ] Existing stream/status tracking is either migrated or wrapped so it fits the shared presentation model.
- [ ] The implementation distinguishes reusable UI surfaces from append-only content where necessary.
- [ ] There are tests showing that status/streaming flows do not regress while adopting the shared model.

### US-005: Make channel capabilities declarative at the presentation boundary
**Description:** As a maintainer, I want channel capabilities represented declaratively so that orchestration and presentation logic stay generic.

**Acceptance Criteria:**
- [ ] The system exposes capability checks through a shared boundary rather than scattered adapter conditionals.
- [ ] Presentation logic can ask whether a channel supports replacement, editing, components, or related capabilities without naming specific channels.
- [ ] Adding a new channel requires wiring capabilities, not copying orchestration logic.
- [ ] Existing Telegram and Discord behavior continues to pass current tests.

### US-006: Document and harden the presentation architecture
**Description:** As a maintainer, I want the presentation model documented so that future UI work follows the same architectural direction instead of reintroducing adapter-local state.

**Acceptance Criteria:**
- [ ] The repo documents the presentation architecture and intended ownership boundaries.
- [ ] The documentation explains where orchestration decisions belong versus where ports/adapters project them.
- [ ] The documentation covers editable surfaces, non-editable fallbacks, and slot/state ownership.
- [ ] At least one representative code path is referenced in the documentation.

## Functional Requirements

1. FR-1: The system must define presentation surface concepts in a core-owned module or boundary that is not channel-specific.
2. FR-2: The system must support named reusable surfaces such as `bootstrap`, `menu`, `config`, `models`, `think`, `help`, and future equivalents.
3. FR-3: The system must preserve channel-specific projection behavior while removing channel-specific ownership of presentation decisions from orchestration logic.
4. FR-4: The system must support channels that can edit/replace messages and channels that cannot, using the same core presentation intent.
5. FR-5: The system must keep independent UI surfaces from clobbering each other within the same user/channel context.
6. FR-6: The system must cover both interactive menu-like UI and ephemeral status/streaming UI within the same architectural framework.
7. FR-7: The system must provide a clear boundary for mutable presentation state, instead of leaving that state embedded in adapter-local tables.
8. FR-8: The system must allow future channels to opt into presentation capabilities declaratively.

## Non-Goals

- Rewriting every outbound path in one shot.
- Replacing all channel-specific rendering code with a universal renderer.
- Changing the product copy or interaction wording unless needed for regression fixes.
- Solving unrelated security, memory, or provider-routing concerns in the same refactor.
- Adding brand-new user-facing features beyond the presentation architecture needed to support existing flows.

## Technical Considerations

- The current code already contains partial building blocks:
  - `replacementSlot` in outbound messages
  - shared outbound replacement handling
  - shared slot helpers in `common_runtime`
- The next step should avoid another temporary layer that merely shifts state around without changing ownership.
- The target boundary is a port-complete presentation surface in the core, not just more helpers in adapters.
- Status and streaming should be included in scope early, otherwise the architecture will remain split between “interactive UI” and “special-case runtime UI”.
- The migration should proceed in slices that preserve working Telegram and Discord behavior at every step.

## Success Metrics

- The orchestrator and other core flows stop naming specific channels for presentation behavior.
- Telegram and Discord runtime code shrink in local UI-state bookkeeping responsibilities.
- New replaceable surfaces can be added by defining presentation intent rather than inventing new per-adapter tables.
- Status/streaming and interactive menus follow the same architectural vocabulary.
- Tests covering outbound/presentation behavior stay green throughout the migration.

## Open Questions

- Should streaming surfaces live in the same state store as replaceable menus, or in a sibling presentation state component?
- Should the presentation surface boundary own fallback copy for non-editable channels, or should that stay in runtime projection code?
- How far should the first implementation go for channels beyond Telegram and Discord?
- Should the final boundary live under `core/outbound`, `domain/presentation`, or a new port namespace?
[/PRD]
