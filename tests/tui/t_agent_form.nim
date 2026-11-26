## Typing an agent in the admin TUI (PRD-roadmap E6.2): a small form, pure,
## fed key codes (illwill's are ASCII), that gives back the agent to save.

import std/unittest
import donkey/tui/agent_form
import donkey/domain/agents/named_agent_pure

proc typeText(f: var AgentForm; s: string) =
  for c in s:
    discard f.handleKey(ord(c))

proc runTests*() =
  suite "agent form":

    test "a new agent is typed field by field and submitted with Enter":
      var f = newAgentForm()
      typeText(f, "suporte")
      check f.handleKey(KeyTab) == feNone
      typeText(f, "Atende clientes")
      discard f.handleKey(KeyTab)
      typeText(f, "openrouter")
      discard f.handleKey(KeyTab)
      typeText(f, "x/y")
      check f.handleKey(KeyEnter) == feSubmit
      let a = f.agent()
      check a.name == "suporte" and a.description == "Atende clientes"
      check a.provider == "openrouter" and a.model == "x/y"
      check not f.editing

    test "Backspace erases, Esc cancels, the arrows move between fields":
      var f = newAgentForm()
      typeText(f, "abcx")
      discard f.handleKey(KeyBackspace)
      check f.values[0] == "abc"
      discard f.handleKey(KeyDown)
      check f.field == 1
      discard f.handleKey(KeyUp)
      check f.field == 0
      discard f.handleKey(KeyUp)
      check f.field == 0          ## no field above the first
      check f.handleKey(KeyEscape) == feCancel

    test "editing keeps the name fixed and fills the other fields":
      var f = editAgentForm(NamedAgent(name: "suporte", description: "d",
                                       provider: "p", model: "m"))
      check f.editing and f.field == 1
      check f.values == @["suporte", "d", "p", "m"]
      typeText(f, "!")
      check f.values[1] == "d!"
      discard f.handleKey(KeyUp)
      check f.field == 1          ## the name cannot be reached while editing

    test "while editing, the name cannot be typed even with the cursor on it":
      var f = editAgentForm(NamedAgent(name: "suporte", description: "d"))
      f.field = 0
      typeText(f, "x")
      check f.values[0] == "suporte"
      f.field = 0
      discard f.handleKey(KeyBackspace)
      check f.values[0] == "suporte"

    test "control characters are not typed; the length is bounded":
      var f = newAgentForm()
      discard f.handleKey(1)
      discard f.handleKey(200)
      check f.values[0] == ""
      for _ in 0 ..< MaxFieldLen + 10:
        discard f.handleKey(ord('a'))
      check f.values[0].len == MaxFieldLen

    test "Enter on an empty name or description does not submit":
      var f = newAgentForm()
      check f.handleKey(KeyEnter) == feInvalid
      check f.error.len > 0

when isMainModule:
  runTests()
