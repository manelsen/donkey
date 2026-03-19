import unittest
import donkey/domain/reminder

suite "parseWhen — relative offsets":

  test "+30m":
    let now = 1_700_000_000'i64
    check parseWhen("+30m", now) == now + 1_800

  test "+2h":
    let now = 1_700_000_000'i64
    check parseWhen("+2h", now) == now + 7_200

  test "+1d":
    let now = 1_700_000_000'i64
    check parseWhen("+1d", now) == now + 86_400

  test "+90m":
    let now = 1_700_000_000'i64
    check parseWhen("+90m", now) == now + 5_400

  test "sem unidade trata como minutos":
    let now = 1_700_000_000'i64
    check parseWhen("+45x", now) == now + 45 * 60

suite "parseWhen — ISO 8601":

  test "UTC com Z":
    let ts = parseWhen("2025-01-01T12:00:00Z", 0)
    check ts == 1_735_732_800'i64   ## 2025-01-01 12:00:00 UTC

  test "com offset negativo":
    ## 2025-01-01T09:00:00-03:00 == 2025-01-01T12:00:00Z
    let ts = parseWhen("2025-01-01T09:00:00-03:00", 0)
    check ts == 1_735_732_800'i64

  test "falha graciosamente — retorna now+1h":
    let now = 1_700_000_000'i64
    let ts  = parseWhen("INVALID_DATE", now)
    check ts == now + 3_600

suite "parseWhen — strings com espaços":

  test "strip de espaços":
    let now = 1_700_000_000'i64
    check parseWhen("  +10m  ", now) == now + 600
