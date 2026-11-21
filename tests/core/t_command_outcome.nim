## Command outcome contract: who may see a reply, whether the channel owes an
## acknowledgement, and the no-session text for each session command.

import std/[strutils, unittest]
import donkey/core/commands/command_routing
import donkey/core/commands/command_outcome

proc runTests*() =
  suite "command outcome: visibility":
    test "every local action maps to a topic":
      for action in LocalCommandAction:
        discard localActionTopic(action)

    test "identity, link and diagnostic actions are requester-only":
      for action in [lcaGenerateLinkCode, lcaContinueLink, lcaDoctorReport,
                     lcaShowMemory, lcaShowWhoami]:
        check topicVisibility(localActionTopic(action)) == rvRequesterOnly

    test "the remaining local actions are public":
      for action in [lcaShowAbout, lcaStartIntro, lcaSkillCommand,
                     lcaClearMemory, lcaHelpText, lcaShowMenu,
                     lcaReasoningToggle]:
        check topicVisibility(localActionTopic(action)) == rvPublic

    test "replied derives visibility from the topic":
      check replied(rtLinkCode, "code").reply.visibility == rvRequesterOnly
      check replied(rtLinkCode, "code").reply.requesterOnly
      check replied(rtAbout, "about").reply.visibility == rvPublic
      check replied(rtContinue, "x", failed = true).reply.failed

  suite "command outcome: acknowledgement":
    test "an accepted task is an outcome of its own, not silence":
      let o = accepted(cmdStop)
      check o.kind == cokAccepted
      check o.task == cmdStop
      check acceptedText(cmdStop).len > 0

    test "every session-task command has an acknowledgement text":
      for kind in CommandKind:
        if decideCommandRoute(kind) == crSessionTask:
          check acceptedText(kind).len > 0

    test "unsupported replies are not sent on plain-text channels":
      check not replied(rtUnsupported, UnsupportedCommandText).reply.shouldSend
      check replied(rtHelp, "help").reply.shouldSend
      check not replied(rtHelp, "").reply.shouldSend

  suite "command outcome: no-session text":
    test "every session-task command has a no-session text":
      for kind in CommandKind:
        if decideCommandRoute(kind) == crSessionTask:
          check noSessionText(kind).len > 0

    test "only /reset talks about restarting a conversation":
      check "reiniciar" in noSessionText(cmdReset)
      for kind in [cmdCompact, cmdStop, cmdDebug]:
        check "reiniciar" notin noSessionText(kind)

    test "/compact and /stop say what they could not do":
      check "compactar" in noSessionText(cmdCompact)
      check "parar" in noSessionText(cmdStop)

when isMainModule:
  runTests()
