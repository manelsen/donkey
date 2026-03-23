## Tests for domain/tools/shell_ast — pure shell operator detection functions.

import std/[unittest, strutils]
import donkey/domain/tools/shell_ast

suite "isShellOperatorChar":

  test "pipe is operator":
    check isShellOperatorChar('|')

  test "semicolon is operator":
    check isShellOperatorChar(';')

  test "ampersand is operator":
    check isShellOperatorChar('&')

  test "less than is operator":
    check isShellOperatorChar('<')

  test "greater than is operator":
    check isShellOperatorChar('>')

  test "alphanumeric is not operator":
    check not isShellOperatorChar('a')
    check not isShellOperatorChar('Z')
    check not isShellOperatorChar('0')

  test "space is not operator":
    check not isShellOperatorChar(' ')

  test "special chars are not operators":
    check not isShellOperatorChar('.')
    check not isShellOperatorChar('/')
    check not isShellOperatorChar('-')
    check not isShellOperatorChar('_')

suite "containsShellOperators":

  test "clean command returns false":
    check not containsShellOperators("ls -la")
    check not containsShellOperators("echo hello")
    check not containsShellOperators("cat file.txt")
    check not containsShellOperators("git status")

  test "pipe detected":
    check containsShellOperators("ls | grep foo")
    check containsShellOperators("cat file | head")

  test "semicolon detected":
    check containsShellOperators("ls; cat file")
    check containsShellOperators("echo a; echo b")

  test "ampersand detected":
    check containsShellOperators("ls &")
    check containsShellOperators("cat file &")

  test "redirect detected":
    check containsShellOperators("cat < file")
    check containsShellOperators("echo hi > out")

  test "combined operators detected":
    check containsShellOperators("cat < in | grep foo > out")

suite "hasPipe":

  test "no pipe returns false":
    check not hasPipe("ls -la")
    check not hasPipe("git status")

  test "single pipe returns true":
    check hasPipe("ls | grep foo")
    check hasPipe("cat file | head")

  test "double pipe (or) returns false for pipe detection":
    # Note: || contains | but is logically different
    check hasPipe("cat || ls")

suite "hasSemicolon":

  test "no semicolon returns false":
    check not hasSemicolon("ls -la")
    check not hasSemicolon("echo hello")

  test "semicolon returns true":
    check hasSemicolon("ls; cat file")
    check hasSemicolon("echo a; echo b")

suite "hasAmpersand":

  test "no ampersand returns false":
    check not hasAmpersand("ls -la")
    check not hasAmpersand("echo hello")

  test "single ampersand returns true":
    check hasAmpersand("ls &")
    check hasAmpersand("cat file &")

  test "double ampersand (&&) contains ampersand":
    check hasAmpersand("ls && cat file")

suite "hasInputRedirect":

  test "no redirect returns false":
    check not hasInputRedirect("ls -la")
    check not hasInputRedirect("echo hello")

  test "input redirect returns true":
    check hasInputRedirect("cat < file")
    check hasInputRedirect("grep foo < input.txt")

suite "hasOutputRedirect":

  test "no redirect returns false":
    check not hasOutputRedirect("ls -la")
    check not hasOutputRedirect("echo hello")

  test "output redirect returns true":
    check hasOutputRedirect("echo hi > out")
    check hasOutputRedirect("cat file > output.txt")

suite "hasCommandSeparator":

  test "no semicolon returns false":
    check not hasCommandSeparator("ls -la")

  test "semicolon returns true":
    check hasCommandSeparator("ls; cat file")

suite "hasLogicalAnd":

  test "no && returns false":
    check not hasLogicalAnd("ls -la")
    check not hasLogicalAnd("ls & cat")

  test "&& returns true":
    check hasLogicalAnd("ls && cat file")
    check hasLogicalAnd("echo a && echo b")

suite "hasLogicalOr":

  test "no || returns false":
    check not hasLogicalOr("ls -la")
    check not hasLogicalOr("ls | cat")

  test "|| returns true":
    check hasLogicalOr("ls || cat file")
    check hasLogicalOr("echo a || echo b")

suite "hasOutputAppend":

  test "no >> returns false":
    check not hasOutputAppend("ls > file")
    check not hasOutputAppend("echo hi")

  test ">> returns true":
    check hasOutputAppend("echo hi >> log.txt")
    check hasOutputAppend("cat file >> out")

suite "hasStderrRedirect":

  test "no 2> returns false":
    check not hasStderrRedirect("ls > file")
    check not hasStderrRedirect("echo hi")

  test "2> returns true":
    check hasStderrRedirect("grep foo 2> errors.txt")
    check hasStderrRedirect("cmd 2>&1")

suite "hasBackgroundOperator":

  test "no & returns false":
    check not hasBackgroundOperator("ls -la")

  test "& returns true":
    check hasBackgroundOperator("ls &")
    check hasBackgroundOperator("cat file &")

suite "hasRedirect":

  test "no redirect returns false":
    check not hasRedirect("ls -la")

  test "input redirect detected":
    check hasRedirect("cat < file")

  test "output redirect detected":
    check hasRedirect("echo hi > out")

  test "combined redirects detected":
    check hasRedirect("cat < in > out")

suite "hasCompoundOperator":

  test "no compound operator returns false":
    check not hasCompoundOperator("ls -la")
    check not hasCompoundOperator("ls > file")

  test "&& returns true":
    check hasCompoundOperator("ls && cat")

  test "|| returns true":
    check hasCompoundOperator("ls || cat")

  test ">> returns true":
    check hasCompoundOperator("echo hi >> log")

  test "2> returns true":
    check hasCompoundOperator("grep foo 2> err")

suite "detectShellOperators":

  test "clean input returns empty":
    let detected = detectShellOperators("ls -la")
    check detected.len == 0

  test "pipe detected":
    let detected = detectShellOperators("ls | grep foo")
    check sokPipe in detected

  test "semicolon detected":
    let detected = detectShellOperators("ls; cat file")
    check sokSemicolon in detected

  test "ampersand detected":
    let detected = detectShellOperators("ls &")
    check sokAmpersand in detected

  test "input redirect detected":
    let detected = detectShellOperators("cat < file")
    check sokInputRedirect in detected

  test "output redirect detected":
    let detected = detectShellOperators("echo hi > out")
    check sokOutputRedirect in detected

  test "logical AND detected":
    let detected = detectShellOperators("ls && cat")
    check sokLogicalAnd in detected

  test "logical OR detected":
    let detected = detectShellOperators("ls || cat")
    check sokLogicalOr in detected

  test "output append detected":
    let detected = detectShellOperators("echo hi >> log")
    check sokOutputAppend in detected

  test "stderr redirect detected":
    let detected = detectShellOperators("grep foo 2> err")
    check sokStderrRedirect in detected

  test "multiple operators detected":
    let detected = detectShellOperators("cat < in | grep foo > out &")
    check sokInputRedirect in detected
    check sokPipe in detected
    check sokOutputRedirect in detected
    check sokAmpersand in detected

  test "compound && and || don't double-count pipes":
    let detected = detectShellOperators("ls || cat | wc")
    check sokLogicalOr in detected
    check sokPipe in detected

suite "validateShellSafe":

  test "clean input returns valid":
    let v = validateShellSafe("ls -la")
    check v.isClean
    check v.normalized == "ls -la"

  test "stripped whitespace preserved":
    let v = validateShellSafe("  ls -la  ")
    check v.isClean
    check v.normalized == "ls -la"

  test "pipe returns invalid":
    let v = validateShellSafe("ls | grep foo")
    check not v.isClean
    check sokPipe in v.operators

  test "semicolon returns invalid":
    let v = validateShellSafe("ls; cat file")
    check not v.isClean
    check sokSemicolon in v.operators

  test "ampersand returns invalid":
    let v = validateShellSafe("ls &")
    check not v.isClean
    check sokAmpersand in v.operators

  test "redirect returns invalid":
    let v = validateShellSafe("cat < file")
    check not v.isClean
    check sokInputRedirect in v.operators

  test "multiple operators captured":
    let v = validateShellSafe("cat < in | grep foo > out &")
    check not v.isClean
    check v.operators.len == 4

suite "isShellSafe":

  test "clean command is safe":
    check isShellSafe("ls -la")
    check isShellSafe("git status")
    check isShellSafe("echo hello world")
    check isShellSafe("cat file.txt")

  test "pipe is unsafe":
    check not isShellSafe("ls | grep foo")

  test "semicolon is unsafe":
    check not isShellSafe("ls; cat file")

  test "ampersand is unsafe":
    check not isShellSafe("ls &")

  test "redirect is unsafe":
    check not isShellSafe("cat < file")
    check not isShellSafe("echo hi > out")

suite "shellValidationErrorMsg":

  test "clean input gives generic error":
    check shellValidationErrorMsg("ls -la") == "Error: invalid input"

  test "single operator gives specific error":
    let msg = shellValidationErrorMsg("ls | grep foo")
    check msg.contains("pipe")
    check msg.contains("blocked")

  test "multiple operators listed":
    let msg = shellValidationErrorMsg("cat < in | grep foo > out &")
    check msg.contains("multiple")

suite "shellBlockReason":

  test "clean input gives clean reason":
    check shellBlockReason("ls -la") == "input is clean"

  test "single operator reason":
    let reason = shellBlockReason("ls | grep foo")
    check reason.contains("pipe")

  test "multiple operators reason":
    let reason = shellBlockReason("ls & cat")
    check reason.contains("&&") == false  # just &
