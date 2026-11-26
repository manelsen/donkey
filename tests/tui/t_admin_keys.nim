## The admin panel's letter keys work with or without Shift: the footer
## writes them in capitals ("[D] delete"), and illwill gives Shift+D its own
## code (Key.ShiftD), apart from Key.D.

import std/[options, unittest]
import illwill
import donkey/tui/admin_keys

proc runTests*() =
  suite "admin keys":

    test "a letter and its Shift give the same action":
      check actionChar(Key.D) == some('D')
      check actionChar(Key.ShiftD) == some('D')
      check actionChar(Key.A) == some('A')
      check actionChar(Key.ShiftA) == some('A')
      check actionChar(Key.X) == some('X')
      check actionChar(Key.ShiftX) == some('X')
      check actionChar(Key.Enter) == some('E')

    test "other keys are not actions":
      check actionChar(Key.Q) == none(char)
      check actionChar(Key.None) == none(char)

    test "N opens the form, R refreshes, with or without Shift":
      check isKey(Key.ShiftN, 'N') and isKey(Key.N, 'N')
      check isKey(Key.ShiftR, 'R') and isKey(Key.R, 'R')
      check not isKey(Key.D, 'N')

when isMainModule:
  runTests()
