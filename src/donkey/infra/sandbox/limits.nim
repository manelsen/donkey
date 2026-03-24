## infra/sandbox/limits — OS resource limit wrappers (setrlimit).
##
## Provides cgroups/rlimit-style CPU and memory restrictions for native tools.
## Uses Linux setrlimit(2) — pure Nim, no external C dependencies.
##
## Usage:
##   limits.setCpuLimit(60).isOkOr: echo "failed: " & error
##   limits.setMemLimit(512 * 1024 * 1024).isOkOr: echo "failed: " & error
##
## All functions return Result[T, string] so callers decide what to do on error.
## Functions are designed as unary or with the piped target as last argument to
## facilitate `|>` and `>>=` chaining where applicable.

import std/posix

import ../../core/pipeops

export pipeops

# ── Linux rlimit constants ──────────────────────────────────────────────────────
## RLIMIT_* resource constants from <sys/resource.h>

const
  RLIMIT_CPU* = 0  ## CPU time limit (seconds)
  RLIMIT_AS*  = 9  ## Address space (bytes) — virtual memory
  RLIMIT_NPROC* = 6 ## Max processes per user
  RLIMIT_FSIZE* = 1 ## Max file size (bytes)
  RLIMIT_NOFILE* = 7 ## Max open files

  # In Nim's RLimit, rlim_cur/rlim_max are int.
  # -1 represents RLIM_INFINITY (unlimited) when cast appropriately.
  # We use a very large positive number to mean "unlimited" internally.
  RlimInfinityInternal* = -1

type
  ResourceKind* = distinct cint
    ## RLIMIT_CPU, RLIMIT_AS, RLIMIT_NPROC, etc.

  LimitResult* = Result[void, string]
    ## Result type for limit-setting operations.

  CpuLimit* = distinct int64
    ## CPU time limit in seconds.

  MemLimit* = distinct int64
    ## Memory limit in bytes.

  NprocLimit* = distinct int64
    ## Max number of processes.

  FsizeLimit* = distinct int64
    ## Max file size in bytes.

  NofileLimit* = distinct int64
    ## Max number of open files.

  CurrentLimits* = object
    ## Snapshot of all resource limits.
    cpu*:    int64
    mem*:    int64
    nproc*:  int64
    fsize*:  int64
    nofile*: int64

# ── Equality operators for distinct types ──────────────────────────────────────

func `==`*(a, b: CpuLimit): bool = a.int64 == b.int64
func `==`*(a, b: MemLimit): bool = a.int64 == b.int64
func `==`*(a, b: NprocLimit): bool = a.int64 == b.int64
func `==`*(a, b: FsizeLimit): bool = a.int64 == b.int64
func `==`*(a, b: NofileLimit): bool = a.int64 == b.int64

# ── Conversion helpers ─────────────────────────────────────────────────────────

func toRlim*(x: int64): int =
  ## Convert int64 limit to RLimit int field. 0 means unlimited.
  if x <= 0:
    RlimInfinityInternal
  else:
    x.int

func fromRlim*(x: int): int64 =
  ## Convert RLimit int field to int64. -1 (infinity) becomes 0.
  if x == RlimInfinityInternal:
    0
  else:
    x.int64

# ── Pure helper: errno to string ───────────────────────────────────────────────

func errnoString*(err: cint): string =
  case err
  of EPERM:   "Operation not permitted"
  of EINVAL:  "Invalid argument"
  of EFAULT:  "Bad address"
  of ESRCH:   "No such process"
  of ENOMEM:  "Cannot allocate memory"
  else:       "Unknown error (" & $err & ")"

# ── CPU limit ─────────────────────────────────────────────────────────────────

proc setrlimitCpu*(cpuSecs: CpuLimit): LimitResult =
  var lim: RLimit
  lim.rlim_cur = cpuSecs.int64.toRlim
  lim.rlim_max = cpuSecs.int64.toRlim
  if setrlimit(RLIMIT_CPU.cint, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitCpu*(): int64 =
  var lim: RLimit
  if getrlimit(RLIMIT_CPU.cint, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── Memory (address space) limit ───────────────────────────────────────────────

proc setrlimitMem*(bytes: MemLimit): LimitResult =
  var lim: RLimit
  lim.rlim_cur = bytes.int64.toRlim
  lim.rlim_max = bytes.int64.toRlim
  if setrlimit(RLIMIT_AS.cint, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitMem*(): int64 =
  var lim: RLimit
  if getrlimit(RLIMIT_AS.cint, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── NPROC limit ────────────────────────────────────────────────────────────────

proc setrlimitNproc*(maxProcs: NprocLimit): LimitResult =
  var lim: RLimit
  lim.rlim_cur = maxProcs.int64.toRlim
  lim.rlim_max = maxProcs.int64.toRlim
  if setrlimit(RLIMIT_NPROC.cint, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitNproc*(): int64 =
  var lim: RLimit
  if getrlimit(RLIMIT_NPROC.cint, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── File size limit ────────────────────────────────────────────────────────────

proc setrlimitFsize*(bytes: FsizeLimit): LimitResult =
  var lim: RLimit
  lim.rlim_cur = bytes.int64.toRlim
  lim.rlim_max = bytes.int64.toRlim
  if setrlimit(RLIMIT_FSIZE.cint, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitFsize*(): int64 =
  var lim: RLimit
  if getrlimit(RLIMIT_FSIZE.cint, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── NOFILE limit ──────────────────────────────────────────────────────────────

proc setrlimitNofile*(maxFiles: NofileLimit): LimitResult =
  var lim: RLimit
  lim.rlim_cur = maxFiles.int64.toRlim
  lim.rlim_max = maxFiles.int64.toRlim
  if setrlimit(RLIMIT_NOFILE.cint, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitNofile*(): int64 =
  var lim: RLimit
  if getrlimit(RLIMIT_NOFILE.cint, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── Snapshot all limits ───────────────────────────────────────────────────────

func snapshotLimits*(): CurrentLimits =
  CurrentLimits(
    cpu:    getrlimitCpu(),
    mem:    getrlimitMem(),
    nproc:  getrlimitNproc(),
    fsize:  getrlimitFsize(),
    nofile: getrlimitNofile(),
  )

# ── Apply a complete limit set ────────────────────────────────────────────────

proc applyLimits*(cpu: CpuLimit; mem: MemLimit; nproc: NprocLimit;
                  fsize: FsizeLimit; nofile: NofileLimit): LimitResult =
  ## Set all resource limits at once. Short-circuits on first failure.
  let cpuRes = cpu.setrlimitCpu()
  if cpuRes.isErr:
    return err(cpuRes.error)
  let memRes = mem.setrlimitMem()
  if memRes.isErr:
    return err(memRes.error)
  let nprocRes = nproc.setrlimitNproc()
  if nprocRes.isErr:
    return err(nprocRes.error)
  let fsizeRes = fsize.setrlimitFsize()
  if fsizeRes.isErr:
    return err(fsizeRes.error)
  nofile.setrlimitNofile()

# ── Convenience constructors ───────────────────────────────────────────────────

func cpuSeconds*(s: int64): CpuLimit = CpuLimit(s)
func memBytes*(b: int64): MemLimit = MemLimit(b)
func nprocCount*(n: int64): NprocLimit = NprocLimit(n)
func fsizeBytes*(b: int64): FsizeLimit = FsizeLimit(b)
func nofileCount*(n: int64): NofileLimit = NofileLimit(n)

# ── Zero-limit aliases for clearing ────────────────────────────────────────────

func unlimited*(_: typedesc[CpuLimit]): CpuLimit  = CpuLimit(0)
func unlimited*(_: typedesc[MemLimit]): MemLimit  = MemLimit(0)
func unlimited*(_: typedesc[NprocLimit]): NprocLimit = NprocLimit(0)
func unlimited*(_: typedesc[FsizeLimit]): FsizeLimit = FsizeLimit(0)
func unlimited*(_: typedesc[NofileLimit]): NofileLimit = NofileLimit(0)

# ── Formatting helpers ─────────────────────────────────────────────────────────

func `$`*(lim: CpuLimit): string =
  let s = lim.int64
  if s <= 0: "unlimited" else: $s & "s"

func `$`*(lim: MemLimit): string =
  let b = lim.int64
  if b <= 0: "unlimited"
  elif b < 1024: $b & "B"
  elif b < 1024*1024: $((b + 512) div 1024) & "KB"
  elif b < 1024*1024*1024: $((b + 512*1024) div (1024*1024)) & "MB"
  else: $((b + 512*1024*1024) div (1024*1024*1024)) & "GB"

func `$`*(lim: NprocLimit): string =
  let n = lim.int64
  if n <= 0: "unlimited" else: $n

func `$`*(lim: FsizeLimit): string =
  let b = lim.int64
  if b <= 0: "unlimited"
  elif b < 1024*1024: $((b + 512) div 1024) & "KB"
  elif b < 1024*1024*1024: $((b + 512*1024) div (1024*1024)) & "MB"
  else: $((b + 512*1024*1024) div (1024*1024*1024)) & "GB"

func `$`*(lim: NofileLimit): string =
  let n = lim.int64
  if n <= 0: "unlimited" else: $n

func `$`*(limits: CurrentLimits): string =
  "CurrentLimits(cpu=" & $(CpuLimit(limits.cpu)) &
           ", mem=" & $(MemLimit(limits.mem)) &
           ", nproc=" & $(NprocLimit(limits.nproc)) &
           ", fsize=" & $(FsizeLimit(limits.fsize)) &
           ", nofile=" & $(NofileLimit(limits.nofile)) & ")"
