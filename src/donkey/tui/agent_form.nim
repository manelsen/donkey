## agent_form — typing an agent in the admin TUI (PRD-roadmap E6.2).
##
## Pure: a form of four fields (name, description, provider, model) fed key
## codes. illwill's codes are ASCII for printable keys; the arrows have their
## own codes here, mapped by the caller. Enter submits a form whose name and
## description are filled; while editing an existing agent the name is fixed.

import std/strutils
import ../domain/agents/named_agent_pure
import ../domain/agents/agent_name_pure

const
  KeyTab* = 9
  KeyEnter* = 13
  KeyEscape* = 27
  KeyBackspace* = 127
  KeyUp* = -101   ## not an illwill code (its None is -1)
  KeyDown* = -102
  MaxFieldLen* = 200
  FieldLabels* = ["Nome", "Descrição (persona)", "Provider (opcional)", "Modelo (opcional)"]

type
  FormEvent* = enum
    feNone, feSubmit, feCancel, feInvalid

  AgentForm* = object
    values*:  seq[string]
    field*:   int
    editing*: bool     ## an existing agent: its name is fixed
    error*:   string

func newAgentForm*(): AgentForm =
  AgentForm(values: @["", "", "", ""])

func editAgentForm*(a: NamedAgent): AgentForm =
  AgentForm(values: @[a.name, a.description, a.provider, a.model], field: 1, editing: true)

func firstField(f: AgentForm): int = (if f.editing: 1 else: 0)

func agent*(f: AgentForm): NamedAgent =
  NamedAgent(name: f.values[0].strip.toLowerAscii, description: f.values[1].strip,
             provider: f.values[2].strip, model: f.values[3].strip)

func handleKey*(f: var AgentForm; code: int): FormEvent =
  f.error = ""
  case code
  of KeyEscape:
    return feCancel
  of KeyEnter:
    let a = f.agent()
    if not validAgentName(a.name):
      f.error = "o nome tem de 1 a 32 letras minúsculas, dígitos ou '-'"
      return feInvalid
    if a.description.len == 0:
      f.error = "a descrição é obrigatória"
      return feInvalid
    return feSubmit
  of KeyTab, KeyDown:
    f.field = min(f.field + 1, f.values.high)
  of KeyUp:
    f.field = max(f.field - 1, f.firstField)
  of KeyBackspace, 8:
    if f.values[f.field].len > 0:
      f.values[f.field].setLen(f.values[f.field].len - 1)
  of 32 .. 126:
    if f.values[f.field].len < MaxFieldLen:
      f.values[f.field].add chr(code)
  else:
    discard
  feNone
