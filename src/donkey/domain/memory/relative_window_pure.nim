## relative_window_pure — a relative date in a question, as a time window.
##
## "What did we talk about 3 days ago?" asks about a period, not about the
## newest memories. Recall's temporal policy ranked by recency over all time,
## so today's memories won. When a question names a relative date, this
## module gives the period it means; recall then ranks by recency inside it.
##
## English and Portuguese, accents folded (as the recall words are):
## - yesterday / ontem; the day before / anteontem; today / hoje;
## - N days, weeks or months ago / há N … / N … atrás, in digits or words:
##   a day for days, the 7 days around the date for weeks, the 15 around it
##   for months;
## - last week / semana passada, last month / mês passado;
## - in the last N days, weeks or months / nos últimos N …: then until now.
##
## Days are UTC days. No match, no window: the question is ranked as before.

import std/[options, strutils, unicode]
import ./session_search_pure

type TimeWindow* = object
  fromSec*: int64   ## unix seconds, inclusive
  toSec*:   int64   ## unix seconds, exclusive

const
  DaySec = 86_400'i64
  NumberWords = [
    ("um", 1), ("uma", 1), ("one", 1), ("a", 1), ("an", 1),
    ("dois", 2), ("duas", 2), ("two", 2),
    ("tres", 3), ("three", 3),
    ("quatro", 4), ("four", 4),
    ("cinco", 5), ("five", 5),
    ("seis", 6), ("six", 6),
    ("sete", 7), ("seven", 7),
    ("oito", 8), ("eight", 8),
    ("nove", 9), ("nine", 9),
    ("dez", 10), ("ten", 10)]

type Unit = enum uDay, uWeek, uMonth

func words(query: string): seq[string] =
  ## The folded words in order, repeats kept.
  var current = ""
  for r in foldSearchText(query).runes:
    if r.isAlpha or (r.int >= 48 and r.int <= 57):
      current.add($r)
    elif current.len > 0:
      result.add(current)
      current.setLen(0)
  if current.len > 0:
    result.add(current)

func numberOf(word: string): Option[int] =
  if word.len > 0 and word.allCharsInSet(Digits):
    try:
      let n = parseInt(word)
      if n > 0 and n <= 400: return some(n)
    except ValueError:
      discard
    return none(int)
  for (name, value) in NumberWords:
    if word == name: return some(value)
  none(int)

func unitOf(word: string): Option[Unit] =
  case word
  of "dia", "dias", "day", "days": some(uDay)
  of "semana", "semanas", "week", "weeks": some(uWeek)
  of "mes", "meses", "month", "months": some(uMonth)
  else: none(Unit)

func unitDays(u: Unit): int64 =
  case u
  of uDay: 1
  of uWeek: 7
  of uMonth: 30

func around(today: int64; n: int; u: Unit): TimeWindow =
  ## The period an "N units ago" points at.
  let center = today - int64(n) * unitDays(u) * DaySec
  case u
  of uDay: TimeWindow(fromSec: center, toSec: center + DaySec)
  of uWeek: TimeWindow(fromSec: center - 3 * DaySec, toSec: center + 4 * DaySec)
  of uMonth: TimeWindow(fromSec: center - 7 * DaySec, toSec: center + 8 * DaySec)

func relativeWindow*(query: string; nowSec: int64): Option[TimeWindow] =
  ## The period a question's relative date means; none without one.
  let w = words(query)
  let today = nowSec - (nowSec mod DaySec)
  ## "N units": ago / atrás after, há before; "last/últimos N units" before.
  for i in 0 ..< w.len - 1:
    let n = numberOf(w[i])
    let u = unitOf(w[i + 1])
    if n.isNone or u.isNone:
      continue
    let after = if i + 2 < w.len: w[i + 2] else: ""
    let before = if i > 0: w[i - 1] else: ""
    let before2 = if i > 1: w[i - 2] else: ""
    if after in ["ago", "atras"] or before == "ha":
      return some(around(today, n.get, u.get))
    if before in ["last", "past", "ultimos", "ultimas"] or
       (before == "the" and before2 in ["last", "past"]):
      return some(TimeWindow(fromSec: today - int64(n.get) * unitDays(u.get) * DaySec,
                             toSec: nowSec + 1))
  ## "last week", "semana passada", "last month", "mês passado".
  for i in 0 ..< w.len - 1:
    let pair = (w[i], w[i + 1])
    if pair in [("last", "week"), ("semana", "passada")]:
      return some(TimeWindow(fromSec: today - 14 * DaySec, toSec: today - 6 * DaySec))
    if pair in [("last", "month"), ("mes", "passado")]:
      return some(TimeWindow(fromSec: today - 60 * DaySec, toSec: today - 29 * DaySec))
  if "anteontem" in w:
    return some(TimeWindow(fromSec: today - 2 * DaySec, toSec: today - DaySec))
  if "ontem" in w or "yesterday" in w:
    return some(TimeWindow(fromSec: today - DaySec, toSec: today))
  if "hoje" in w or "today" in w:
    return some(TimeWindow(fromSec: today, toSec: nowSec + 1))
  none(TimeWindow)
