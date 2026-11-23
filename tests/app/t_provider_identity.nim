## t_provider_identity.nim — operator-facing provider lists come from the table.
##
## US-009 characterization: doctor, setup, the service env file and the admin
## TUI must expose the descriptor table instead of a private id/env list.

import std/[options, os, sequtils, sets, strutils, unittest]
import donkey/domain/providers/descriptors
import donkey/config/types
import donkey/app/doctor
import donkey/adapters/filesystem/fs_adapter
import donkey/adapters/process/process_adapter

let testProcess = newProcessAdapter()
let testFs = newFsAdapter()
import donkey/app/setup_wizard
import donkey/app/service_handler
import donkey/tui/admin_tui

func descriptorIds(): seq[string] =
  for d in providerDescriptors():
    result.add d.id

func idSet(values: seq[string]): HashSet[string] =
  for value in values:
    result.incl value

# ── doctor ─────────────────────────────────────────────────────────────────────

proc runTests*() =
  suite "provider identity — doctor":

    test "doctor provider rows cover every descriptor":
      let rows = doctorProviderRows()
      check rows.len == providerDescriptors().len
      let ids = rows.mapIt(it.id)
      for id in descriptorIds():
        check id in ids

    test "doctor provider rows carry the first descriptor env name":
      for row in doctorProviderRows():
        let descriptor = providerDescriptor(row.id).get()
        check row.envVar == descriptor.envNames[0]

    test "doctor rows have unique labels":
      let labels = doctorProviderRows().mapIt(it.label)
      check labels.len == labels.deduplicate().len

    test "runDoctorChecks lists a key check for every descriptor":
      let results = runDoctorChecks(testProcess, testFs, DonkeyConfig(sandboxMode: smNone))
      for row in doctorProviderRows():
        check results.anyIt(it.name == row.label)

  # ── setup wizard ───────────────────────────────────────────────────────────────

  suite "provider identity — setup wizard":

    test "setup provider menu covers every descriptor":
      let ids = setupProviderIds()
      check ids.len == providerDescriptors().len
      for id in descriptorIds():
        check id in ids

    test "setup provider env var is the first descriptor env name":
      for id in descriptorIds():
        let descriptor = providerDescriptor(id).get()
        check providerEnvVar(id) == descriptor.envNames[0]

    test "unknown provider still has no env var":
      check providerEnvVar("unknown") == ""

    test "doctor and setup expose the same provider set":
      check idSet(doctorProviderRows().mapIt(it.id)) == idSet(setupProviderIds())

    test "doctor and setup agree on every provider env var":
      for row in doctorProviderRows():
        check providerEnvVar(row.id) == row.envVar

  # ── service handler ────────────────────────────────────────────────────────────

  suite "provider identity — service handler":

    test "service env keys contain every descriptor env name":
      let keys = serviceEnvKeys()
      for descriptor in providerDescriptors():
        for envName in descriptor.envNames:
          check envName in keys

    test "service env template mentions every provider env name":
      let envTemplate = buildEnvFileTemplate()
      for descriptor in providerDescriptors():
        check descriptor.envNames[0] & "=" in envTemplate

  # ── admin TUI ──────────────────────────────────────────────────────────────────

  suite "provider identity — admin TUI":

    test "TUI known providers cover every descriptor":
      let ids = tuiKnownProviders()
      check ids.len == providerDescriptors().len
      for id in descriptorIds():
        check id in ids

    test "TUI provider fallback matches the single source":
      var st = newAdminState()
      st.loadProviderItems()
      check st.items.mapIt(it.name) == tuiKnownProviders()

    test "TUI keeps a single provider list":
      let source = readFile(currentSourcePath().parentDir.parentDir.parentDir /
                            "src" / "donkey" / "tui" / "admin_tui.nim")
      check source.count("const knownProviders") == 0
      check source.count("func tuiKnownProviders*()") == 1

when isMainModule:
  runTests()
