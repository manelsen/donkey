import std/unittest
import std/options
import donkey/core/types
import donkey/core/routing/group_routing

suite "Group Routing":

  test "GroupId operations":
    let gid = GroupId("group123")
    check $gid == "group123"
    check isValidGroupId(gid) == true
    let emptyGid = GroupId("")
    check isValidGroupId(emptyGid) == false

  test "findGroupConfig finds existing group":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      name: "Test Group",
      mentionRequired: true
    )
    let registry = GroupAgentRegistry(
      defaultAgent: "default",
      groups: @[config]
    )
    let found = findGroupConfig(registry, GroupId("group1"))
    check found.isSome()
    check found.get().name == "Test Group"

  test "findGroupConfig returns none for missing group":
    let registry = GroupAgentRegistry(
      defaultAgent: "default",
      groups: @[]
    )
    let found = findGroupConfig(registry, GroupId("nonexistent"))
    check found.isNone()

  test "isToolAllowed allows non-restricted tools":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      blockedTools: @["dangerous_tool"],
      allowedTools: @[]
    )
    check isToolAllowed(config, "read_file") == true
    check isToolAllowed(config, "dangerous_tool") == false

  test "isToolAllowed respects allowedTools list":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      allowedTools: @["read_file", "grep"]
    )
    check isToolAllowed(config, "read_file") == true
    check isToolAllowed(config, "bash") == false

  test "needsMention returns group setting":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      mentionRequired: true
    )
    check needsMention(config) == true
    let noMentionConfig = GroupConfig(
      groupId: GroupId("group2"),
      mentionRequired: false
    )
    check needsMention(noMentionConfig) == false

  test "getPersonalityOverride returns override when set":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      personality: "helpful_coder"
    )
    check getPersonalityOverride(config) == some("helpful_coder")

  test "getPersonalityOverride returns none when not set":
    let config = GroupConfig(
      groupId: GroupId("group1"),
      personality: ""
    )
    check getPersonalityOverride(config).isNone()
