## file_tools — send_file (E9.6): a file from the person's paddock to the
## channel of the conversation.
##
## Only a channel whose adapter reads a paddock file and uploads it
## (cfSendFile: Telegram, Mattermost) is handed the file; the adapter reads it
## confined to the paddock (confined_read). Elsewhere nothing goes out and the
## agent is told where the file is, to tell the person.

import std/[options, os, strutils]
import ../../core/pipeops
import ../../core/types
import ../../domain/message
import ../../ports/channel_capability
import ../../ports/fs

type SendFileOutcome* = object
  text*:     string                    ## what the tool answers the model
  outbound*: Option[OutboundMessage]   ## the message to send, when the channel can

proc prepareSendFile*(fs: FsRuntimePort; paddockDir, path, caption: string;
                      channel: ChannelKind; uid: UserId;
                      replyTo: string): Result[SendFileOutcome, string] =
  ## `path` is already resolved inside the paddock.
  if fs.entryKind(path) != fekFile:
    return err("send_file: no such file in the workspace: " & path)
  let shown = relativePath(path, paddockDir)
  if not supports(channel, cfSendFile):
    return ok(SendFileOutcome(text: "This channel (" & $channel & ") cannot " &
      "receive files from the workspace. Tell the person the file is saved at " &
      shown & " in their workspace."))
  ok(SendFileOutcome(
    text: "File sent: " & shown,
    outbound: some(OutboundMessage(userId: uid, channel: channel, text: caption,
                                   replyTo: replyTo, mediaUrl: path,
                                   mediaRoot: paddockDir))))
