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

const
  RlimInfinity* = 0xFFFFFFFFFFFFFFFF'u64
  ## RLIM_INFINITY — no limit (64-bit Linux)

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

# ── rlimit syscall wrappers ────────────────────────────────────────────────────

func toRlim*(x: int64): rlim_t =
  if x <= 0:
    RlimInfinity
  else:
    x.rlim_t

func fromRlim*(x: rlim_t): int64 =
  if x == RlimInfinity:
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

func setrlimitCpu*(cpuSecs: CpuLimit): LimitResult =
  var lim: rlimit
  lim.rlim_cur = cpuSecs.int64.toRlim
  lim.rlim_max = cpuSecs.int64.toRlim
  if setrlimit(RLIMIT_CPU, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitCpu*(): int64 =
  var lim: rlimit
  if getrlimit(RLIMIT_CPU, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── Memory (address space) limit ───────────────────────────────────────────────

func setrlimitMem*(bytes: MemLimit): LimitResult =
  var lim: rlimit
  lim.rlim_cur = bytes.int64.toRlim
  lim.rlim_max = bytes.int64.toRlim
  if setrlimit(RLIMIT_AS, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitMem*(): int64 =
  var lim: rlimit
  if getrlimit(RLIMIT_AS, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── NPROC limit ────────────────────────────────────────────────────────────────

func setrlimitNproc*(maxProcs: NprocLimit): LimitResult =
  var lim: rlimit
  lim.rlim_cur = maxProcs.int64.toRlim
  lim.rlim_max = maxProcs.int64.toRlim
  if setrlimit(RLIMIT_NPROC, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitNproc*(): int64 =
  var lim: rlimit
  if getrlimit(RLIMIT_NPROC, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── File size limit ────────────────────────────────────────────────────────────

func setrlimitFsize*(bytes: FsizeLimit): LimitResult =
  var lim: rlimit
  lim.rlim_cur = bytes.int64.toRlim
  lim.rlim_max = bytes.int64.toRlim
  if setrlimit(RLIMIT_FSIZE, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitFsize*(): int64 =
  var lim: rlimit
  if getrlimit(RLIMIT_FSIZE, lim) == 0:
    lim.rlim_cur.fromRlim
  else:
    0

# ── NOFILE limit ──────────────────────────────────────────────────────────────

func setrlimitNofile*(maxFiles: NofileLimit): LimitResult =
  var lim: rlimit
  lim.rlim_cur = maxFiles.int64.toRlim
  lim.rlim_max = maxFiles.int64.toRlim
  if setrlimit(RLIMIT_NOFILE, lim) < 0:
    err errnoString(errno)
  else:
    ok()

func getrlimitNofile*(): int64 =
  var lim: rlimit
  if getrlimit(RLIMIT_NOFILE, lim) == 0:
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

func applyLimits*(cpu: CpuLimit; mem: MemLimit; nproc: NprocLimit;
                  fsize: FsizeLimit; nofile: NofileLimit): LimitResult =
  ## Set all resource limits at once. Short-circuits on first failure.
  cpu.setrlimitCpu() >>= func(_: void): LimitResult =
    mem.setrlimitMem() >>= func(_: void): LimitResult =
      nproc.setrlimitNproc() >>= func(_: void): LimitResult =
        fsize.setrlimitFsize() >>= func(_: void): LimitResult =
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
  "CurrentLimits(cpu=" & $limits.cpu &
           ", mem=" & $limits.mem &
           ", nproc=" & $limits.nproc &
           ", fsize=" & $limits.fsize &
           ", nofile=" & $limits.nofile & ")"
