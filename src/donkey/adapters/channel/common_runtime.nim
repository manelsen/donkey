## Channel runtime helpers: UI slots for editable keyboards and the wiring
## every channel runtime receives. Command policy lives in
## `app/command_dispatch`; texts in `core/commands/command_text`; model
## pickers in `model_catalog_ui`; MdFile-backed effects in `command_services`.

import std/tables
import ../../core/commands/command_text
import ../../core/outbound/outbound
import ../../adapters/memory/md_file
import ../../adapters/memory/channel_prefs_store
import ../../app/command_dispatch
import ../../domain/message
import ../../ports/provider
import ../../core/commands/command_routing
import ../identity/identity_resolver
import ./command_services
import ./model_catalog_ui
import ../../core/commands/preference_commands
import ../../core/pipeops

export command_text, channel_prefs_store, model_catalog_ui, command_services
export preference_commands.preferencesUnreadableText

proc configViewText*(memory: MdFileAdapter; userId: UserId;
                     withButtons = true): Result[string, string] =
  ## The /config view of the user's preferences. Presentation belongs to the
  ## channels; the store only reads.
  ok(buildConfigText(? memory.loadChannelPrefs(userId), withButtons))

const UiSlotMenu* = "menu"
const UiSlotConfig* = "config"
const UiSlotModels* = "models"
const UiSlotThink* = "think"
const UiSlotHelp* = "help"

func uiSlotKey*(userId: UserId; slot: string): string =
  $userId & "|" & slot

proc getUiMsgId*(state: PresentationState;
                 channel: ChannelKind;
                 userId: UserId;
                 slot: string): string =
  state.replacementMsgIds.getOrDefault(replacementSurfaceKey(channel, userId, slot))

proc setUiMsgId*(state: var PresentationState;
                 channel: ChannelKind;
                 userId: UserId;
                 slot, msgId: string) =
  if msgId.len > 0:
    state.replacementMsgIds[replacementSurfaceKey(channel, userId, slot)] = msgId

proc clearUiMsgId*(state: var PresentationState;
                   channel: ChannelKind;
                   userId: UserId;
                   slot: string) =
  state.replacementMsgIds.del(replacementSurfaceKey(channel, userId, slot))



type
  ChannelRuntimeEnv* = object
    ## What every channel runtime receives: the command policy (`commands`)
    ## plus the daemon state its own presentation needs (pickers, menus).
    commands*:           CommandEnv
    memory*:             MdFileAdapter
    completeBuilder*:    proc(preferencesMd: string): CompleteFn {.gcsafe.}
    modelCatalogLoader*: ModelCatalogLoader
    toolsCount*:         int
    toolClientsCount*:   int
    daemonStartMs*:      int64

proc newChannelRuntimeEnv*(memory: MdFileAdapter;
                           completeBuilder: proc(preferencesMd: string): CompleteFn {.gcsafe.};
                           modelCatalogLoader: ModelCatalogLoader;
                           toolsCount = 0;
                           toolClientsCount = 0;
                           daemonStartMs = 0'i64): ChannelRuntimeEnv =
  ChannelRuntimeEnv(
    commands: CommandEnv(services: newCommandServices(
      memory, completeBuilder, modelCatalogLoader, toolsCount, toolClientsCount,
      daemonStartMs)),
    memory: memory,
    completeBuilder: completeBuilder,
    modelCatalogLoader: modelCatalogLoader,
    toolsCount: toolsCount,
    toolClientsCount: toolClientsCount,
    daemonStartMs: daemonStartMs,
  )

proc commandRequest*(command: CommandDecision; userId: UserId;
                     channel: ChannelKind; messageId, rawId: string;
                     resolver: IdentityResolver): CommandDispatchRequest =
  ## The dispatch request of a plain-text channel: `/continue` links the
  ## speaker's raw id, tasks reply to `messageId`.
  CommandDispatchRequest(
    command: command, userId: userId, channel: channel, messageId: messageId,
    rawId: rawId, links: resolver.identityLinkPort())
