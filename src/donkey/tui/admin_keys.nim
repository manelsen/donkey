## admin_keys — the admin panel's letter keys, with or without Shift.
##
## The footer writes them in capitals ("[D] delete") and illwill gives a
## shifted letter its own code (Key.ShiftD = 'D', Key.D = 'd'): matching only
## Key.D ignored Shift+D, and an action needed several presses.

import std/options
import illwill

func isKey*(key: Key; letter: char): bool =
  ## `letter` is a capital; the key is it or its lowercase.
  ord(key) == ord(letter) or ord(key) == ord(letter) + 32

func actionChar*(key: Key): Option[char] =
  ## The action letter `adminKeyFor` takes: Enter is 'E'.
  if key == Key.Enter: return some('E')
  for letter in ['A', 'D', 'X']:
    if isKey(key, letter): return some(letter)
  none(char)
