import std/[strutils, posix]
import unittest2
import ../../../src/donkey/infra/sandbox/limits
import ../../../src/donkey/core/pipeops

suite "infra/sandbox/limits":

  suite "toRlim / fromRlim":
    test "toRlim: zero becomes infinity":
      check toRlim(0) == RlimInfinityInternal

    test "toRlim: positive value passed through":
      check toRlim(60) == 60

    test "toRlim: negative becomes infinity":
      check toRlim(-1) == RlimInfinityInternal

    test "fromRlim: infinity becomes zero":
      check fromRlim(RlimInfinityInternal) == 0

    test "fromRlim: finite value passed through":
      check fromRlim(120) == 120

  suite "CpuLimit formatting":
    test "zero shows as unlimited":
      check $CpuLimit(0) == "unlimited"

    test "positive shows as seconds":
      check $CpuLimit(60) == "60s"

    test "large value formats correctly":
      check $CpuLimit(3600) == "3600s"

  suite "MemLimit formatting":
    test "zero shows as unlimited":
      check $MemLimit(0) == "unlimited"

    test "bytes under KB":
      check $MemLimit(512) == "512B"

    test "bytes at KB boundary":
      check $MemLimit(1024) == "1KB"

    test "KB range":
      check $MemLimit(512 * 1024) == "512KB"

    test "MB range":
      check $MemLimit(100 * 1024 * 1024) == "100MB"

    test "GB range":
      check $MemLimit(2 * 1024 * 1024 * 1024) == "2GB"

  suite "NprocLimit formatting":
    test "zero shows as unlimited":
      check $NprocLimit(0) == "unlimited"

    test "positive shows as count":
      check $NprocLimit(10) == "10"

  suite "FsizeLimit formatting":
    test "zero shows as unlimited":
      check $FsizeLimit(0) == "unlimited"

    test "KB range":
      check $FsizeLimit(100 * 1024) == "100KB"

    test "MB range":
      check $FsizeLimit(50 * 1024 * 1024) == "50MB"

    test "GB range":
      check $FsizeLimit(1 * 1024 * 1024 * 1024) == "1GB"

  suite "NofileLimit formatting":
    test "zero shows as unlimited":
      check $NofileLimit(0) == "unlimited"

    test "positive shows as count":
      check $NofileLimit(1024) == "1024"

  suite "Convenience constructors":
    test "cpuSeconds":
      check cpuSeconds(30) == CpuLimit(30)

    test "memBytes":
      check memBytes(1024) == MemLimit(1024)

    test "nprocCount":
      check nprocCount(5) == NprocLimit(5)

    test "fsizeBytes":
      check fsizeBytes(4096) == FsizeLimit(4096)

    test "nofileCount":
      check nofileCount(256) == NofileLimit(256)

  suite "unlimited constructors":
    test "CpuLimit.unlimited":
      check unlimited(CpuLimit) == CpuLimit(0)

    test "MemLimit.unlimited":
      check unlimited(MemLimit) == MemLimit(0)

    test "NprocLimit.unlimited":
      check unlimited(NprocLimit) == NprocLimit(0)

    test "FsizeLimit.unlimited":
      check unlimited(FsizeLimit) == FsizeLimit(0)

    test "NofileLimit.unlimited":
      check unlimited(NofileLimit) == NofileLimit(0)

  suite "snapshotLimits":
    test "returns CurrentLimits":
      let snap = snapshotLimits()
      check snap.cpu >= 0
      check snap.mem >= 0
      check snap.nproc >= 0
      check snap.fsize >= 0
      check snap.nofile >= 0

  suite "CurrentLimits formatting":
    test "shows all fields":
      let limits = CurrentLimits(cpu: 60, mem: 1024, nproc: 10, fsize: 4096, nofile: 256)
      let s = $limits
      check s.contains("cpu=60s")
      check s.contains("mem=1KB")
      check s.contains("nproc=10")
      check s.contains("fsize=4KB")
      check s.contains("nofile=256")

  suite "getrlimit getters":
    test "getrlimitCpu returns non-negative":
      check getrlimitCpu() >= 0

    test "getrlimitMem returns non-negative":
      check getrlimitMem() >= 0

    test "getrlimitNproc returns non-negative":
      check getrlimitNproc() >= 0

    test "getrlimitFsize returns non-negative":
      check getrlimitFsize() >= 0

    test "getrlimitNofile returns non-negative":
      check getrlimitNofile() >= 0

  suite "setrlimitCpu (may fail without privileges)":
    test "setting valid CPU limit either succeeds or reports error":
      let result = setrlimitCpu(CpuLimit(300))
      # Either succeeds or returns a meaningful error
      if result.isErr:
        let errMsg = result.error
        check errMsg.len > 0
        # Common errors: EPERM if not privileged, EINVAL if value is weird
        check errMsg == "Operation not permitted" or errMsg == "Invalid argument"

    test "clearing CPU limit either succeeds or reports error":
      let result = setrlimitCpu(CpuLimit(0))  # 0 = unlimited
      if result.isErr:
        let errMsg = result.error
        check errMsg == "Operation not permitted" or errMsg == "Invalid argument"

  suite "setrlimitMem (may fail without privileges)":
    test "setting valid memory limit either succeeds or reports error":
      let result = setrlimitMem(MemLimit(1024 * 1024 * 1024))  # 1GB
      if result.isErr:
        let errMsg = result.error
        check errMsg == "Operation not permitted" or errMsg == "Invalid argument"

  suite "setrlimitNproc (may fail without privileges)":
    test "setting nproc limit either succeeds or reports error":
      let result = setrlimitNproc(NprocLimit(100))
      if result.isErr:
        let errMsg = result.error
        check errMsg == "Operation not permitted" or errMsg == "Invalid argument"

  suite "applyLimits (may fail without privileges)":
    test "applying all limits either succeeds or reports error":
      let result = applyLimits(
        CpuLimit(300),
        MemLimit(1024 * 1024 * 1024),
        NprocLimit(100),
        FsizeLimit(1024 * 1024 * 1024),
        NofileLimit(1024)
      )
      if result.isErr:
        let errMsg = result.error
        # Short-circuits on first failure
        check errMsg == "Operation not permitted" or errMsg == "Invalid argument"

  suite "errnoString":
    test "EPERM":
      check errnoString(EPERM) == "Operation not permitted"

    test "EINVAL":
      check errnoString(EINVAL) == "Invalid argument"

    test "EFAULT":
      check errnoString(EFAULT) == "Bad address"

    test "unknown errno":
      check errnoString(9999).contains("Unknown error")
