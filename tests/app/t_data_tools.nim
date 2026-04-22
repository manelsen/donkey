import std/[json, os, times, unittest]

import donkey/app/tools/data_tools
import donkey/app/tools/fs_tools
import donkey/app/tools/search_tools

suite "runJsonQuery":

  test "get returns a nested value":
    let request = %*{
      "op": "get",
      "input": {
        "user": {
          "name": "Ana",
          "prefs": {"lang": "pt-BR"}
        }
      },
      "path": ["user", "prefs", "lang"]
    }

    let result = runJsonQuery(request).toNode()

    check result["ok"].getBool()
    check result["status"].getStr() == "output"
    check result["data"]["value"].getStr() == "pt-BR"

  test "set replaces a nested value":
    let request = %*{
      "op": "set",
      "input": {
        "user": {
          "name": "Ana",
          "prefs": {"lang": "en"}
        }
      },
      "path": ["user", "prefs", "lang"],
      "value": "pt-BR"
    }

    let result = runJsonQuery(request).toNode()

    check result["ok"].getBool()
    check result["data"]["value"]["user"]["prefs"]["lang"].getStr() == "pt-BR"

  test "delete removes object keys and array entries":
    let objectDelete = %*{
      "op": "delete",
      "input": {
        "user": {
          "name": "Ana",
          "prefs": {"lang": "pt-BR"}
        }
      },
      "path": ["user", "prefs"]
    }
    let objectResult = runJsonQuery(objectDelete).toNode()
    check objectResult["ok"].getBool()
    check not objectResult["data"]["value"]["user"].hasKey("prefs")

    let arrayDelete = %*{
      "op": "delete",
      "input": {"langs": ["pt", "en", "es"]},
      "path": ["langs", 1]
    }
    let arrayResult = runJsonQuery(arrayDelete).toNode()
    check arrayResult["ok"].getBool()
    check arrayResult["data"]["value"]["langs"].len == 2
    check arrayResult["data"]["value"]["langs"][0].getStr() == "pt"
    check arrayResult["data"]["value"]["langs"][1].getStr() == "es"

  test "merge performs a recursive object merge":
    let request = %*{
      "op": "merge",
      "input": {
        "user": {
          "name": "Ana",
          "prefs": {"lang": "en", "theme": "light"}
        }
      },
      "patch": {
        "user": {
          "prefs": {"lang": "pt-BR"},
          "role": "admin"
        }
      }
    }

    let result = runJsonQuery(request).toNode()

    check result["ok"].getBool()
    check result["data"]["value"]["user"]["name"].getStr() == "Ana"
    check result["data"]["value"]["user"]["prefs"]["lang"].getStr() == "pt-BR"
    check result["data"]["value"]["user"]["prefs"]["theme"].getStr() == "light"
    check result["data"]["value"]["user"]["role"].getStr() == "admin"

  test "invalid requests become usage_error":
    let result = runJsonQuery(%*{
      "op": "set",
      "input": {"user": {"name": "Ana"}},
      "path": ["user", "name"]
    }).toNode()

    check not result["ok"].getBool()
    check result["status"].getStr() == "usage_error"
    check result["error"]["message"].getStr().len > 0

suite "runTableQuery":

  test "where, select, sort and limit compose over row arrays":
    let request = %*{
      "rows": [
        {"name": "docs", "kind": "dir", "size": 0},
        {"name": "b.txt", "kind": "file", "size": 20},
        {"name": "a.txt", "kind": "file", "size": 10}
      ],
      "where": [
        {"field": "kind", "op": "eq", "value": "file"}
      ],
      "select": ["name", "size"],
      "sort": [
        {"field": "size", "order": "asc"}
      ],
      "limit": 1
    }

    let result = runTableQuery(request).toNode()
    let rows = result["data"]["rows"]

    check result["ok"].getBool()
    check rows.len == 1
    check rows[0]["name"].getStr() == "a.txt"
    check rows[0]["size"].getInt() == 10
    check not rows[0].hasKey("kind")

  test "multiple filters and descending sort work on generic objects":
    let request = %*{
      "rows": [
        {"name": "a.txt", "kind": "file", "size": 10, "score": 0.8},
        {"name": "b.txt", "kind": "file", "size": 20, "score": 0.3},
        {"name": "docs", "kind": "dir", "size": 0, "score": 0.9}
      ],
      "where": [
        {"field": "kind", "op": "eq", "value": "file"},
        {"field": "size", "op": "gte", "value": 10}
      ],
      "sort": [
        {"field": "score", "order": "desc"},
        {"field": "name", "order": "asc"}
      ]
    }

    let result = runTableQuery(request).toNode()
    let rows = result["data"]["rows"]

    check result["ok"].getBool()
    check rows.len == 2
    check rows[0]["name"].getStr() == "a.txt"
    check rows[1]["name"].getStr() == "b.txt"

  test "invalid table requests become usage_error":
    let result = runTableQuery(%*{
      "rows": {"name": "not-an-array"}
    }).toNode()

    check not result["ok"].getBool()
    check result["status"].getStr() == "usage_error"
    check result["error"]["message"].getStr().len > 0

  test "accepts fs_list envelope without manual extraction":
    let paddock = getTempDir() / ("donkey_table_fs_" & $epochTime())
    createDir(paddock)
    defer:
      if dirExists(paddock):
        removeDir(paddock)

    createDir(paddock / "docs")
    writeFile(paddock / "b.txt", "bbb\n")
    writeFile(paddock / "a.txt", "a\n")

    let fsEnvelope = performFsList(".", paddock, recursive = true).toNode()
    let result = runTableQuery(%*{
      "input": fsEnvelope,
      "where": [{"field": "kind", "op": "eq", "value": "file"}],
      "select": ["path", "size"],
      "sort": [{"field": "path", "order": "asc"}]
    }).toNode()

    check result["ok"].getBool()
    check result["data"]["rows"].len == 2
    check result["data"]["rows"][0]["path"].getStr() == "a.txt"
    check result["data"]["rows"][1]["path"].getStr() == "b.txt"

  test "accepts grep envelope without manual extraction":
    let paddock = getTempDir() / ("donkey_table_grep_" & $epochTime())
    createDir(paddock)
    defer:
      if dirExists(paddock):
        removeDir(paddock)

    let target = paddock / "notes.txt"
    writeFile(target, "alpha\nneedle beta\nneedle gamma\n")

    let grepEnvelope = performGrepStructured("needle", target, false, 20).toNode()
    let result = runTableQuery(%*{
      "input": grepEnvelope,
      "select": ["line", "text"],
      "sort": [{"field": "line", "order": "desc"}],
      "limit": 1
    }).toNode()

    check result["ok"].getBool()
    check result["data"]["rows"].len == 1
    check result["data"]["rows"][0]["line"].getInt() == 3
    check result["data"]["rows"][0]["text"].getStr() == "needle gamma"

  test "rows_path can override automatic array detection":
    let request = %*{
      "input": {
        "data": {
          "nested": {
            "records": [
              {"name": "a", "score": 1},
              {"name": "b", "score": 2}
            ]
          },
          "rows": [
            {"name": "wrong", "score": 999}
          ]
        }
      },
      "rows_path": ["data", "nested", "records"],
      "sort": [{"field": "score", "order": "desc"}]
    }

    let result = runTableQuery(request).toNode()

    check result["ok"].getBool()
    check result["data"]["rows"].len == 2
    check result["data"]["rows"][0]["name"].getStr() == "b"
