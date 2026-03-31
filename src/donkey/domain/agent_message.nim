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
    tkDebugToggle        ## toggles verbose debug mode in the orchestrator
    tkPersonalityChoice  ## payload = "personality:dim:valor" (inline keyboard callback)
    tkNameChoice         ## payload = "name:<chosen-name>" (name selection callback)
    tkCompact            ## trigger session context compaction
    tkNew                ## start a new session (clear context)
    tkStop               ## abort current turn and return to idle
    tkRestart            ## alias for reset/new
    tkBind               ## associate chat with personality

  AgentMessage* = object
    kind*:     AgentMessageKind
    id*:       string
    taskKind*: TaskKind
    userId*:   string
    payload*:  string
    text*:     string
    channel*:  ChannelKind
    replyTo*:  string

func newTaskMsg*(id: string; kind: TaskKind; userId, payload: string;
                 channel = ckTelegram; replyTo = ""): AgentMessage =
  AgentMessage(kind: amkTask, id: id, taskKind: kind,
               userId: userId, payload: payload,
               channel: channel, replyTo: replyTo)

func newCancelMsg*(): AgentMessage =
  AgentMessage(kind: amkCancel)

func newResultMsg*(id, text: string): AgentMessage =
  AgentMessage(kind: amkResult, id: id, text: text, payload: text)

func newErrorMsg*(id, text: string): AgentMessage =
  AgentMessage(kind: amkError, id: id, text: text, payload: text)
