## A question about a relative date ("3 days ago", "há duas semanas",
## "ontem") becomes a time window, so recall ranks by recency inside that
## period instead of over all time.

import std/[options, unittest]
import donkey/domain/memory/relative_window_pure

const
  Day = 86_400'i64
  Now = 1_800_000_000'i64            ## a fixed "now", in unix seconds
  Today = Now - (Now mod Day)        ## midnight UTC that day

proc window(q: string): Option[TimeWindow] = relativeWindow(q, Now)

proc runTests*() =
  suite "relative dates in a question":

    test "yesterday and the day before, today":
      check window("o que falamos ontem?").get == TimeWindow(fromSec: Today - Day, toSec: Today)
      check window("what did we discuss yesterday").get == TimeWindow(fromSec: Today - Day, toSec: Today)
      check window("e anteontem?").get == TimeWindow(fromSec: Today - 2*Day, toSec: Today - Day)
      check window("o que eu disse hoje").get == TimeWindow(fromSec: Today, toSec: Now + 1)

    test "N days, weeks or months ago, in digits or words":
      ## A day around the date: "3 days ago" is that day.
      check window("what did I say 3 days ago").get ==
            TimeWindow(fromSec: Today - 3*Day, toSec: Today - 2*Day)
      check window("o que eu falei há 3 dias").get ==
            TimeWindow(fromSec: Today - 3*Day, toSec: Today - 2*Day)
      check window("três dias atrás").get ==
            TimeWindow(fromSec: Today - 3*Day, toSec: Today - 2*Day)
      ## a week ago: the 7 days around it
      check window("two weeks ago").get ==
            TimeWindow(fromSec: Today - 14*Day - 3*Day, toSec: Today - 14*Day + 4*Day)
      check window("há um mês").get ==
            TimeWindow(fromSec: Today - 30*Day - 7*Day, toSec: Today - 30*Day + 8*Day)

    test "last week, last month: the period before this one":
      check window("o que fizemos semana passada").get ==
            TimeWindow(fromSec: Today - 14*Day, toSec: Today - 7*Day + Day)
      check window("last week").get ==
            TimeWindow(fromSec: Today - 14*Day, toSec: Today - 7*Day + Day)
      check window("no mês passado").get ==
            TimeWindow(fromSec: Today - 60*Day, toSec: Today - 30*Day + Day)

    test "the last few days: from then until now":
      check window("nos últimos 5 dias").get == TimeWindow(fromSec: Today - 5*Day, toSec: Now + 1)
      check window("in the last 2 weeks").get == TimeWindow(fromSec: Today - 14*Day, toSec: Now + 1)

    test "no relative date, no window":
      check window("qual é a senha do wifi?").isNone
      check window("which came first, the trip or the move?").isNone
      check window("o último livro que eu li").isNone   ## "last" without a period
      check window("contem ontem não").get == TimeWindow(fromSec: Today - Day, toSec: Today)

when isMainModule:
  runTests()
