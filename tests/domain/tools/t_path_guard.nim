## Tests for domain/tools/path_guard — pure path security functions.

import std/[unittest, strutils]
import donkey/domain/tools/path_guard

suite "normalizePath":

  test "empty string returns empty":
    check normalizePath("") == ""

  test "single dot returns dot":
    check normalizePath(".") == "."

  test "double dot is blocked":
    check normalizePath("..") == ".."

  test "trailing slash removed":
    check normalizePath("foo/") == "foo"

  test "multiple slashes collapsed":
    check normalizePath("foo//bar") == "foo/bar"
    check normalizePath("foo///bar/baz") == "foo/bar/baz"

  test "dot components removed":
    check normalizePath("foo/./bar") == "foo/bar"
    check normalizePath("./foo") == "foo"

  test "double dot traversal resolved":
    check normalizePath("foo/../bar") == "bar"
    check normalizePath("/foo/../bar") == "/bar"
    check normalizePath("foo/bar/../../baz") == "baz"

  test "leading slash preserved for absolute":
    check normalizePath("/foo/bar") == "/foo/bar"
    check normalizePath("/") == "/"

  test "complex traversal chain":
    check normalizePath("a/b/../c/./d") == "a/c/d"

  test "relative path with dots":
    check normalizePath("./foo/../bar/baz") == "bar/baz"

  test "only slashes becomes root":
    check normalizePath("///") == "/"

suite "splitPath":

  test "simple file":
    let (dir, file) = splitPath("foo.txt")
    check dir == "."
    check file == "foo.txt"

  test "path with directory":
    let (dir, file) = splitPath("foo/bar.txt")
    check dir == "foo"
    check file == "bar.txt"

  test "absolute path":
    let (dir, file) = splitPath("/foo/bar.txt")
    check dir == "/foo"
    check file == "bar.txt"

  test "root file":
    let (dir, file) = splitPath("/foo.txt")
    check dir == "/"
    check file == "foo.txt"

  test "empty becomes dot":
    let (dir, file) = splitPath("")
    check dir == "."
    check file == "."

  test "only slash":
    let (dir, file) = splitPath("/")
    check dir == "/"
    check file == ""

  test "nested path":
    let (dir, file) = splitPath("a/b/c/file.txt")
    check dir == "a/b/c"
    check file == "file.txt"

suite "containsPathTraversal":

  test "clean path returns false":
    check not containsPathTraversal("foo/bar.txt")
    check not containsPathTraversal("foo_bar.txt")
    check not containsPathTraversal(".hidden")

  test "dot dot returns true":
    check containsPathTraversal("../foo")
    check containsPathTraversal("foo/../bar")
    check containsPathTraversal("../")
    check containsPathTraversal("foo/../etc/passwd")
    check containsPathTraversal("./../etc/passwd")

suite "isPathTraversalAttempt":

  test "clean relative path":
    check not isPathTraversalAttempt("foo/bar.txt")
    check not isPathTraversalAttempt("a/b/c")
    check not isPathTraversalAttempt(".hidden")

  test "dot dot traversal blocked":
    check isPathTraversalAttempt("../foo")
    check isPathTraversalAttempt("../etc/passwd")
    check isPathTraversalAttempt("foo/../bar")
    check isPathTraversalAttempt("a/b/../../c")

  test "bare double dot blocked":
    check isPathTraversalAttempt("..")

  test "leading slash with traversal":
    check isPathTraversalAttempt("/../foo")
    check isPathTraversalAttempt("/foo/../../bar")

  test "normalized path unchanged is safe":
    let p = normalizePath("foo/./bar/../baz")
    check not isPathTraversalAttempt(p)

suite "isPathInDirectory":

  test "empty workspace means no restriction":
    check isPathInDirectory("foo/bar", "")
    check isPathInDirectory("../etc/passwd", "")

  test "file in workspace":
    check isPathInDirectory("foo/bar.txt", "foo")
    check isPathInDirectory("foo/bar/baz.txt", "foo/bar")

  test "file in absolute workspace":
    check isPathInDirectory("/home/user/foo.txt", "/home/user")
    check isPathInDirectory("/home/user/a/b.txt", "/home/user/a")

  test "relative path in absolute workspace":
    check isPathInDirectory("foo/bar.txt", "/home/user")
    check isPathInDirectory("a/b.txt", "/a/b")

  test "file outside workspace":
    check not isPathInDirectory("foo.txt", "bar")
    check not isPathInDirectory("/etc/passwd", "/home/user")
    check not isPathInDirectory("../../../etc/passwd", "foo")

  test "traversal escapes workspace":
    check not isPathInDirectory("../foo.txt", "bar")
    check not isPathInDirectory("foo/../../bar.txt", "baz")

  test "same directory":
    check isPathInDirectory("foo", "foo")
    check isPathInDirectory("/foo", "/foo")

  test "exact workspace match":
    check isPathInDirectory("foo/bar", "foo/bar")

  test "nested traversal in workspace":
    check isPathInDirectory("a/b/c/d.txt", "a/b")
    check not isPathInDirectory("a/x/d.txt", "a/b")

suite "isPathSafe":

  test "empty path is unsafe":
    check not isPathSafe("")

  test "clean path in workspace":
    check isPathSafe("foo/bar.txt", "foo")
    check isPathSafe("a/b/c.txt", "a/b")

  test "clean path no workspace":
    check isPathSafe("foo/bar.txt")
    check isPathSafe("./foo/bar")  # ./ is just current dir prefix
    check not isPathSafe("../etc/passwd")  # traversal is unsafe even without workspace
    check not isPathSafe("a/../b")  # ../ in path is traversal regardless of outcome

  test "traversal always unsafe":
    check not isPathSafe("../foo")
    check not isPathSafe("foo/../../bar")
    check not isPathSafe("..")

  test "outside workspace unsafe":
    check not isPathSafe("foo.txt", "bar")
    check not isPathSafe("/etc/passwd", "/home/user")

  test "null byte unsafe":
    check not isPathSafe("foo" & '\x00' & "bar")

suite "validatePathAccess":

  test "empty path returns error":
    let v = validatePathAccess("")
    check not v.ok
    check v.error == pveEmptyPath

  test "valid relative path":
    let v = validatePathAccess("foo/bar.txt")
    check v.ok
    check v.normalized == "foo/bar.txt"

  test "valid absolute path":
    let v = validatePathAccess("/home/user/file.txt")
    check v.ok
    check v.normalized == "/home/user/file.txt"

  test "path with dots but no traversal":
    let v = validatePathAccess("foo/./bar/baz")
    check v.ok
    check v.normalized == "foo/bar/baz"

  test "traversal returns error":
    let v = validatePathAccess("../foo")
    check not v.ok
    check v.error == pveTraversalAttempt

  test "traversal with workspace":
    let v = validatePathAccess("../foo", "bar")
    check not v.ok
    check v.error == pveTraversalAttempt

  test "outside workspace returns error":
    let v = validatePathAccess("foo.txt", "bar")
    check not v.ok
    check v.error == pveOutsideWorkspace

  test "within workspace succeeds":
    let v = validatePathAccess("foo/bar.txt", "foo")
    check v.ok
    check v.normalized == "foo/bar.txt"

  test "null byte returns error":
    let v = validatePathAccess("foo" & '\x00' & "bar")
    check not v.ok
    check v.error == pveNullByte

suite "pathAccessErrorMsg":

  test "empty path message":
    check pathAccessErrorMsg("") == "Error: path is empty"

  test "traversal error message":
    let msg = pathAccessErrorMsg("../foo")
    check msg.contains("path traversal")
    check msg.contains("../foo")

  test "outside workspace message":
    let msg = pathAccessErrorMsg("foo.txt", "bar")
    check msg.contains("outside")
    check msg.contains("foo.txt")

  test "null byte message":
    check pathAccessErrorMsg("foo" & '\x00' & "bar") == "Error: null byte in path"
