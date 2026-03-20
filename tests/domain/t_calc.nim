import unittest
import std/strutils
import donkey/domain/calc

suite "evalCalc — basic arithmetic":

  test "addition":
    check evalCalc("2 + 3")   == "5"
    check evalCalc("0 + 0")   == "0"
    check evalCalc("-1 + 1")  == "0"

  test "subtraction":
    check evalCalc("10 - 4")  == "6"
    check evalCalc("0 - 5")   == "-5"

  test "multiplication":
    check evalCalc("3 * 4")   == "12"
    check evalCalc("-2 * 3")  == "-6"

  test "division":
    check evalCalc("15 / 3")  == "5"
    check evalCalc("7 / 2")   == "3.5"

  test "modulo":
    check evalCalc("10 % 3")  == "1"
    check evalCalc("9 % 3")   == "0"

  test "power":
    check evalCalc("2 ** 10") == "1024"
    check evalCalc("3 ** 2")  == "9"
    check evalCalc("4 ** 0")  == "1"

suite "evalCalc — operator precedence":

  test "mul before add":
    check evalCalc("2 + 3 * 4")  == "14"
    check evalCalc("10 - 2 * 3") == "4"

  test "power before mul":
    check evalCalc("2 * 3 ** 2") == "18"   ## 2 * 9

  test "power right-associative":
    check evalCalc("2 ** 3 ** 2") == "512"  ## 2^(3^2) = 2^9

  test "parentheses override precedence":
    check evalCalc("(2 + 3) * 4")  == "20"
    check evalCalc("2 * (3 + 4)")  == "14"

suite "evalCalc — number literals":

  test "hex":
    check evalCalc("0xFF")  == "255"
    check evalCalc("0x10")  == "16"
    check evalCalc("0x0")   == "0"

  test "binary":
    check evalCalc("0b1010") == "10"
    check evalCalc("0b1111") == "15"

  test "octal":
    check evalCalc("0o10")  == "8"
    check evalCalc("0o777") == "511"

  test "decimal float":
    let r = evalCalc("1.5 + 2.5")
    check r == "4"

suite "evalCalc — unary":

  test "unary minus":
    check evalCalc("-5")        == "-5"
    check evalCalc("-(3 + 2)")  == "-5"

  test "double unary":
    check evalCalc("--5") == "5"

suite "evalCalc — errors":

  test "empty":
    check evalCalc("").startsWith("Error")

  test "division by zero":
    check evalCalc("1 / 0").startsWith("Error")

  test "modulo by zero":
    check evalCalc("5 % 0").startsWith("Error")

  test "unbalanced paren":
    check evalCalc("(2 + 3").startsWith("Error")

suite "globMatch":

  test "star matches anything":
    check globMatch("*", "hello.nim")
    check globMatch("*", "")

  test "prefix star":
    check globMatch("*.nim", "foo.nim")
    check not globMatch("*.nim", "foo.py")

  test "suffix star":
    check globMatch("t_*", "t_calc.nim")
    check not globMatch("t_*", "calc.nim")

  test "exact match":
    check globMatch("foo.nim", "foo.nim")
    check not globMatch("foo.nim", "bar.nim")

  test "question mark":
    check globMatch("t?.nim", "t1.nim")
    check not globMatch("t?.nim", "tab.nim")
