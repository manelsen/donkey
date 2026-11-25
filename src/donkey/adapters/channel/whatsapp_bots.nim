## whatsapp_bots — the `[[bots]]` entries on WhatsApp (PRD-roadmap E3.5).
##
## Numbers of one Meta account share its access token and its webhook: every
## number's messages arrive on the same route, each naming the number it was
## sent to (metadata.phone_number_id). So a bot here is the default adapter's
## token with another number: `botForNumber` picks the bot an event belongs
## to, `noteInbound` makes it the person's, and `adapterFor` is what every
## outbound path asks. Media ids belong to the account, so any adapter
## downloads them.

import ../../core/types
import ../../domain/bots_pure
import ./whatsapp

type
  WhatsAppBotSlot* = object
    name*:    string
    adapter*: WhatsAppAdapter

  WhatsAppBots* = object
    slots*:    seq[WhatsAppBotSlot]
      ## Built once at startup and never resized: pointers into it are kept.
    affinity*: BotAffinity

proc buildWhatsAppBots*(specs: openArray[BotSpec];
                        primary: WhatsAppAdapter): (WhatsAppBots, seq[string]) =
  var bots = WhatsAppBots()
  var problems: seq[string]
  for spec in botsOf(specs, ckWhatsApp):
    if primary.accessToken.len == 0 or primary.phoneNumberId.len == 0:
      problems.add "bot " & spec.name & ": WhatsApp bots use the account of " &
                   "WHATSAPP_ACCESS_TOKEN and WHATSAPP_PHONE_NUMBER_ID, which are not set"
      continue
    if spec.phoneNumberId == primary.phoneNumberId:
      problems.add "bot " & spec.name & ": " & spec.phoneNumberId &
                   " is already the default number"
      continue
    var adapter = newWhatsAppAdapter(primary.accessToken, spec.phoneNumberId, "",
                                     apiBase = primary.apiBase)
    adapter.resolver = primary.resolver
    bots.slots.add WhatsAppBotSlot(name: spec.name, adapter: adapter)
  (bots, problems)

proc botForNumber*(bots: ptr WhatsAppBots; primary: ptr WhatsAppAdapter;
                   number: string): (ptr WhatsAppAdapter, string) =
  ## The adapter and bot name of the number an event was sent to; nil for a
  ## number this instance does not serve (WA-001: not ours, not answered).
  if number.len == 0:
    return (nil, "")
  if number == primary[].phoneNumberId:
    return (primary, "")
  for slot in bots[].slots.mitems:
    if slot.adapter.phoneNumberId == number:
      return (addr slot.adapter, slot.name)
  (nil, "")

proc noteInbound*(bots: var WhatsAppBots; userId: UserId; botName: string) =
  bots.affinity.record($userId, botName)

proc adapterFor*(bots: ptr WhatsAppBots; primary: ptr WhatsAppAdapter;
                 userId: UserId): ptr WhatsAppAdapter =
  let name = bots[].affinity.botFor($userId)
  if name.len > 0:
    for slot in bots[].slots.mitems:
      if slot.name == name:
        return addr slot.adapter
  primary
