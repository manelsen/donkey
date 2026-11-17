## Tests for approval command parsing.

import std/unittest
import donkey/core/security/approval


suite "approval command text":

  test "TG-015: approve and deny are recognised":
    check isApprovalCommandText("/approve ab12cd34")
    check isApprovalCommandText("/deny ab12cd34")

  test "TG-015: other text is not an approval command":
    check not isApprovalCommandText("/approve")
    check not isApprovalCommandText("oi")
    check not isApprovalCommandText("/poll")
