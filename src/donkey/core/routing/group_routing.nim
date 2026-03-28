## group_routing — Pure group routing and isolation helpers.
##
## Supports routing messages to different agents based on group/channel.
## Each group can have its own personality and tool restrictions.

import std/options

type
  GroupId* = distinct string

  GroupConfig* = object
    groupId*:        GroupId
    name*:           string        ## Human-readable group name
    personality*:    string        ## Override personality for this group (optional)
    mentionRequired*: bool         ## Bot must be @mentioned to respond (default: true)
    allowedTools*:   seq[string]   ## Empty = all tools allowed
    blockedTools*:   seq[string]   ## Tools explicitly blocked for this group

  GroupAgentRegistry* = object
    defaultAgent*: string          ## Default agent ID
    groups*:       seq[GroupConfig] ## Per-group configurations

func `$`*(id: GroupId): string =
  string(id)

func `==`*(a, b: GroupId): bool =
  string(a) == string(b)

func isValidGroupId*(id: GroupId): bool =
  ## Returns true if the group ID is non-empty.
  string(id).len > 0

func findGroupConfig*(registry: GroupAgentRegistry; groupId: GroupId): Option[GroupConfig] =
  ## Finds the group configuration for a given group ID.
  for config in registry.groups:
    if config.groupId == groupId:
      return some(config)
  none(GroupConfig)

func isToolAllowed*(config: GroupConfig; toolName: string): bool =
  ## Checks if a tool is allowed for this group.
  if config.blockedTools.contains(toolName):
    return false
  if config.allowedTools.len > 0:
    return config.allowedTools.contains(toolName)
  true  ## No restrictions = all allowed

func needsMention*(config: GroupConfig): bool =
  ## Returns true if this group requires the bot to be mentioned.
  config.mentionRequired

func getPersonalityOverride*(config: GroupConfig): Option[string] =
  ## Returns personality override if configured for this group.
  if config.personality.len > 0:
    some(config.personality)
  else:
    none(string)
