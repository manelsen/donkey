## Fixed-capacity text and tables for state shared between threads.
##
## A global holding a `string`, `seq` or `Table` holds GC memory, so code
## that touches it is not gcsafe and needed `{.cast(gcsafe).}` even under a
## lock. These types are plain values (arrays of bytes and numbers): a global
## of them holds nothing the GC owns, so threads share it under a lock with
## no cast at all. The price is a bound: text is truncated (on a UTF-8
## boundary) and a table has a fixed number of keys, with an `_other` bucket
## for the overflow.

type
  FixedText*[N: static int] = object
    len: int
    data: array[N, char]

  FixedEntry[K: static int; V] = object
    key: FixedText[K]
    value: V

  FixedTable*[N, K: static int; V] = object
    ## Up to N keys of at most K bytes. The last slot is reserved for
    ## `OtherKey`, which collects whatever does not fit.
    count: int
    entries: array[N, FixedEntry[K, V]]

const OtherKey* = "_other"

# ── text ──────────────────────────────────────────────────────────────────────

func utf8Cut(s: string; limit: int): int =
  ## The largest prefix length <= limit that does not split a code point.
  if s.len <= limit: return s.len
  result = limit
  while result > 0 and (ord(s[result]) and 0xC0) == 0x80:
    dec result

func toFixed*[N: static int](s: string): FixedText[N] =
  result.len = utf8Cut(s, N)
  for i in 0 ..< result.len:
    result.data[i] = s[i]

func `$`*[N: static int](t: FixedText[N]): string =
  result = newString(t.len)
  for i in 0 ..< t.len:
    result[i] = t.data[i]

func `==`*[N: static int](t: FixedText[N]; s: string): bool =
  if t.len != utf8Cut(s, N): return false
  for i in 0 ..< t.len:
    if t.data[i] != s[i]: return false
  true

# ── tables ────────────────────────────────────────────────────────────────────

func len*[N, K: static int; V](t: FixedTable[N, K, V]): int = t.count

func clear*[N, K: static int; V](t: var FixedTable[N, K, V]) =
  t = default(FixedTable[N, K, V])

func find[N, K: static int; V](t: FixedTable[N, K, V]; key: string): int =
  for i in 0 ..< t.count:
    if t.entries[i].key == key: return i
  -1

func slot[N, K: static int; V](t: var FixedTable[N, K, V]; key: string): int =
  ## The slot for `key`, adding it when there is room; once only the last
  ## slot is left, every new key shares it as `OtherKey`.
  result = t.find(key)
  if result >= 0: return
  let name = if t.count < N - 1: key else: OtherKey
  result = t.find(name)
  if result >= 0: return
  result = t.count
  t.entries[result].key = toFixed[K](name)
  t.entries[result].value = default(V)
  inc t.count

func mgetOrPut*[N, K: static int; V](t: var FixedTable[N, K, V];
                                     key: string): var V =
  t.entries[t.slot(key)].value

func inc*[N, K: static int; V](t: var FixedTable[N, K, V]; key: string;
                               by: V = 1) =
  t.entries[t.slot(key)].value += by

func get*[N, K: static int; V](t: FixedTable[N, K, V]; key: string;
                               default: V = default(V)): V =
  let i = t.find(key)
  if i >= 0: t.entries[i].value else: default

func contains*[N, K: static int; V](t: FixedTable[N, K, V]; key: string): bool =
  t.find(key) >= 0

iterator pairs*[N, K: static int; V](t: FixedTable[N, K, V]): (string, V) =
  for i in 0 ..< t.count:
    yield ($t.entries[i].key, t.entries[i].value)

func hasKey*[N, K: static int; V](t: FixedTable[N, K, V]; key: string): bool =
  t.find(key) >= 0

func `[]`*[N, K: static int; V](t: FixedTable[N, K, V]; key: string): V =
  ## The value under `key`; the zero value when it is absent.
  t.get(key)
