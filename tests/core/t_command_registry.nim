import std/[options, sequtils, unittest]
import donkey/core/command_registry

suite "command registry":

  test "new registry is empty":
    let r = newCommandRegistry()
    check isNone(r.resolve("unknown"))

  test "register and resolve by name":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "test", minArgs: 1,
      handler: proc(args: seq[string]): int = 0,
      context: ccNone, description: "test cmd"))
    let entry = r.resolve("test")
    check isSome(entry)
    check entry.get().name == "test"
    check entry.get().minArgs == 1

  test "dispatch calls handler with args":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "echo", minArgs: 2,
      handler: proc(args: seq[string]): int =
        if args.len >= 3 and args[1] == "hello" and args[2] == "world": 0 else: 1,
      context: ccNone, description: "echo"))

    check r.dispatch(@["echo", "hello", "world"]) == 0
    check r.dispatch(@["echo", "wrong"]) == 1

  test "dispatch returns -1 for unknown command":
    let r = newCommandRegistry()
    check r.dispatch(@["unknown"]) == -1

  test "dispatch returns 2 when args too short":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "needs", minArgs: 3,
      handler: proc(args: seq[string]): int = 99,
      context: ccNone, description: "needs 3"))
    check r.dispatch(@["needs", "one"]) == 2

  test "handler return code propagates":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "fail", minArgs: 1,
      handler: proc(args: seq[string]): int = 1,
      context: ccNone, description: "fail"))
    check r.dispatch(@["fail"]) == 1

  test "listCommands returns all registered":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "a", minArgs: 1,
      handler: proc(args: seq[string]): int = 0,
      context: ccNone, description: "a"))
    r.register(CommandEntry(
      name: "b", minArgs: 1,
      handler: proc(args: seq[string]): int = 0,
      context: ccNone, description: "b"))
    let cmds = r.listCommands()
    check cmds.len == 2
    let names = toSeq(cmds.mapIt(it.name))
    check "a" in names
    check "b" in names

  test "dispatch empty args returns -1":
    let r = newCommandRegistry()
    check r.dispatch(@[]) == -1

  test "context field is stored":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "x", minArgs: 1,
      handler: proc(args: seq[string]): int = 0,
      context: ccConfigLoaded, description: "x"))
    let entry = r.resolve("x")
    check isSome(entry)
    check entry.get().context == ccConfigLoaded

  test "description field is stored":
    let r = newCommandRegistry()
    r.register(CommandEntry(
      name: "doc", minArgs: 1,
      handler: proc(args: seq[string]): int = 0,
      context: ccNone, description: "Shows docs"))
    check r.resolve("doc").get().description == "Shows docs"
