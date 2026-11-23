## The access token several channel APIs hand out (WeCom, DingTalk, the QQ
## official bot): a value that expires, fetched again a little before it
## does. One rule for all of them instead of a copy per adapter.

const AccessTokenSkewSec* = 60'i64
  ## Fetched again this long before it expires, so a request in flight does
  ## not carry a token that runs out on the way.

type AccessToken* = object
  value*:        string
  expiresAtSec*: int64  ## Unix seconds; 0 when never fetched

func issuedToken*(value: string; expiresInSec, nowSec: int64): AccessToken =
  AccessToken(value: value, expiresAtSec: nowSec + expiresInSec)

func isFresh*(t: AccessToken; nowSec: int64;
              skewSec = AccessTokenSkewSec): bool =
  ## Usable now: fetched, and not within `skewSec` of its expiry.
  t.value.len > 0 and t.expiresAtSec - skewSec > nowSec
