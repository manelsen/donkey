import std/[options, unittest]
import donkey/core/security/approval

suite "approval pure":

  test "ids are validated by shape":
    check isValidApprovalId("abcdefgh")
    check not isValidApprovalId("ABC")
    check not isValidApprovalId("abcdefgh!")

  test "parses approval and denial commands":
    check parseApprovalCommand("/approve abcdefgh").get == (id: "abcdefgh", approved: true)
    check parseApprovalCommand("/deny abcdefgh").get == (id: "abcdefgh", approved: false)
    check parseApprovalCommand("/approve").isNone
    check parseApprovalCommand("/approve ABC").isNone
    check parseApprovalCommand("hello").isNone

  test "parses inline callback data":
    check parseApprovalCallback("approval:abcdefgh:allow").get == (id: "abcdefgh", approved: true)
    check parseApprovalCallback("approval:abcdefgh:deny").get == (id: "abcdefgh", approved: false)
    check parseApprovalCallback("approval:abc:allow").isNone
    check parseApprovalCallback("other:abcdefgh:allow").isNone

  test "poll command is recognised":
    check isPollCommand("/poll")
    check isPollCommand("  /poll  ")
    check not isPollCommand("/poll now")

  test "pending request expiry":
    let request = ApprovalRequest(id: "abcdefgh", status: apsPending,
                                  expiresAtMs: 100)
    check isExpired(request, 99) == false
    check isExpired(request, 100) == true
    var approved = request
    approved.status = apsApproved
    check isExpired(approved, 1000) == false
