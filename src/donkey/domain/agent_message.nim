## agent_message — internal actor message bus types.

import ./message

type
  AgentMessageKind* = enum
    amkTask
    amkCancel
    amkResult
    amkError

  TaskKind* = enum
    tkUserMsg
    tkReset
    tkLoadCtx
    tkSaveMem
    tkSavePrefs
    tkInvokeTool
    tkDebugToggle   ## toggles verbose debug mode in the orchestrator

  AgentMessage* = object
    kind*:     AgentMessageKind
    id*:       string
    taskKind*: TaskKind
    userId*:   string
    payload*:  string
    text*:     string
    channel*:  ChannelKind
    replyTo*:  string

proc newTaskMsg*(id: string; kind: TaskKind; userId, payload: string;
                 channel = ckTelegram; replyTo = ""): AgentMessage =
  AgentMessage(kind: amkTask, id: id, taskKind: kind,
               userId: userId, payload: payload,
               channel: channel, replyTo: replyTo)

proc newCancelMsg*(): AgentMessage =
  AgentMessage(kind: amkCancel)

proc newResultMsg*(id, text: string): AgentMessage =
  AgentMessage(kind: amkResult, id: id, text: text, payload: text)

proc newErrorMsg*(id, text: string): AgentMessage =
  AgentMessage(kind: amkError, id: id, text: text, payload: text)
