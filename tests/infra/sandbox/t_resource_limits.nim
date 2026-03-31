## Test resource limits enforcement.

import std/[unittest, strutils, times]
import donkey/infra/sandbox/docker
import donkey/infra/sandbox/limits
import donkey/core/pipeops

suite "Sandbox Resource Limits":

  test "docker container is killed after timeout (HARD CHECK)":
    # Use a short timeout and a long sleep
    let opts = dockerDefaults().withTimeout(2)
    var d = newDockerSandbox(opts)
    
    let start = epochTime()
    let res = d.runContainer(crPython, "import time; time.sleep(10); print('done')")
    let elapsed = epochTime() - start
    
    if res.isErr:
      echo "Docker run failed: " & res.error
      fail()
    else:
      let val = res.get()
      echo "Elapsed: ", elapsed
      echo "TimedOut: ", val.timedOut
      echo "ExitCode: ", val.exitCode
      echo "Output: ", val.stdout
      check val.timedOut == true
      check val.exitCode in {124, 137}
      # If it's a hard timeout, it should have finished in ~2-3 seconds, not 10.
      check elapsed < 5.0

  test "memory limit is enforced":
    let opts = dockerDefaults().withMemLimitDocker(memBytes(64 * 1024 * 1024))
    let args = buildDockerArgs(opts, "echo", @["echo", "hi"])
    check "--memory=67108864" in args
