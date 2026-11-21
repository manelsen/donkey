## t_setup_provider_list.nim — the setup wizard offers exactly the descriptor table.
##
## Characterization guard for the provider menu built by `donkey setup`: the
## wizard must not keep a private id list that can drift from
## `providerDescriptors()`. Labels/order stay curated in the wizard; the ids
## themselves come from the single source of truth.

import std/[sequtils, sets, unittest]
import donkey/domain/providers/descriptors
import donkey/app/setup_wizard

func descriptorIds(): seq[string] =
  for descriptor in providerDescriptors():
    result.add descriptor.id

func idSet(values: seq[string]): HashSet[string] =
  for value in values:
    result.incl value

proc runTests*() =
  suite "setup wizard provider list":

    test "setup provider ids equal the descriptor ids as a set":
      let expected = idSet(descriptorIds())
      let actual = idSet(setupProviderIds())
      check actual == expected
      for id in descriptorIds():
        check id in actual
      for id in setupProviderIds():
        check id in expected

    test "setup provider ids contain no duplicates":
      let ids = setupProviderIds()
      check ids.len == ids.deduplicate().len
      check ids.len == idSet(ids).len

    test "setup provider ids cover every descriptor exactly once":
      let ids = setupProviderIds()
      check ids.len == providerDescriptors().len
      for descriptor in providerDescriptors():
        check ids.count(descriptor.id) == 1

when isMainModule:
  runTests()
