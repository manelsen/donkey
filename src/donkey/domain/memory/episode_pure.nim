## episode_pure — explicit journaled episode units for consolidation.
## Pure functions only. No I/O.

import std/[strutils, sequtils]

type
  EpisodeJournal* = object
    id*:              string
    title*:           string
    summary*:         string
    startTs*:         int64
    endTs*:           int64
    sourceMemoryIds*: seq[string]

func episodeIdFromTitle(title: string): string =
  var words = title.toLowerAscii().mapIt(
    if it.isAlphaNumeric(): it else: ' '
  ).join("").splitWhitespace()
  if words.len == 0:
    return "episode"
  words[0 ..< min(words.len, 5)].join("-")

func episodeId*(title: string; startTs, endTs: int64): string =
  episodeIdFromTitle(title) & "-" & $startTs & "-" & $endTs

func newEpisodeJournal*(title, summary: string;
                        startTs, endTs: int64;
                        sourceMemoryIds: seq[string]): EpisodeJournal =
  let resolvedTitle =
    if title.strip.len > 0: title.strip
    elif summary.strip.len > 0:
      summary.strip.splitLines()[0][0 ..< min(summary.strip.splitLines()[0].len, 48)].strip()
    else:
      "Episode"
  EpisodeJournal(
    id: episodeId(resolvedTitle, startTs, endTs),
    title: resolvedTitle,
    summary: summary.strip(),
    startTs: startTs,
    endTs: max(endTs, startTs),
    sourceMemoryIds: sourceMemoryIds,
  )
