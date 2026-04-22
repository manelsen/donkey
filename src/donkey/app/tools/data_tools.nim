## data_tools.nim — structured JSON and table operations.
##
## This module provides the pure core for the future `json_query` and
## `table_query` native tools. Requests and responses are plain JSON objects so
## the caller can compose them directly without shell parsing or implicit
## session state.

import std/[algorithm, json, sequtils, strutils]

import ../../core/tooling/structured_tool_result

export structured_tool_result

type
  SortOrder = enum
    soAsc
    soDesc

  TableSortSpec = object
    fieldPath: seq[JsonNode]
    order: SortOrder

  TableFilterSpec = object
    fieldPath: seq[JsonNode]
    op: string
    value: JsonNode

proc isNumberNode(node: JsonNode): bool =
  not node.isNil and node.kind in {JInt, JFloat}

proc numberValue(node: JsonNode): float =
  case node.kind
  of JInt: float(node.getInt())
  of JFloat: node.getFloat()
  else: 0.0

proc isSegmentNode(node: JsonNode): bool =
  not node.isNil and node.kind in {JString, JInt}

proc segmentLabel(node: JsonNode): string =
  case node.kind
  of JString: node.getStr()
  of JInt: $node.getInt()
  else: "<invalid>"

proc parsePathNode(node: JsonNode; fieldName: string): tuple[ok: bool, path: seq[JsonNode], message: string] =
  if node.isNil:
    return (false, @[], fieldName & " is required")
  case node.kind
  of JString, JInt:
    (true, @[node.copy()], "")
  of JArray:
    var path: seq[JsonNode] = @[]
    for segment in node:
      if not isSegmentNode(segment):
        return (false, @[], fieldName & " segments must be strings or integers")
      path.add(segment.copy())
    (true, path, "")
  else:
    (false, @[], fieldName & " must be a string, integer, or array of path segments")

proc jsonNodesEqual(a, b: JsonNode): bool =
  if a.isNil or b.isNil:
    return a.isNil and b.isNil
  if isNumberNode(a) and isNumberNode(b):
    return numberValue(a) == numberValue(b)
  if a.kind != b.kind:
    return false
  case a.kind
  of JString: a.getStr() == b.getStr()
  of JInt: a.getInt() == b.getInt()
  of JFloat: a.getFloat() == b.getFloat()
  of JBool: a.getBool() == b.getBool()
  of JNull: true
  else: $a == $b

proc compareJsonNodes(a, b: JsonNode): int =
  if a.isNil and b.isNil:
    return 0
  if a.isNil:
    return -1
  if b.isNil:
    return 1
  if isNumberNode(a) and isNumberNode(b):
    return cmp(numberValue(a), numberValue(b))
  if a.kind == JString and b.kind == JString:
    return cmp(a.getStr(), b.getStr())
  if a.kind == JBool and b.kind == JBool:
    return cmp(ord(a.getBool()), ord(b.getBool()))
  cmp($a, $b)

proc tryGetAtPath(root: JsonNode; path: seq[JsonNode]): JsonNode =
  var current = root
  for segment in path:
    if current.isNil:
      return nil
    case current.kind
    of JObject:
      if segment.kind != JString:
        return nil
      let key = segment.getStr()
      if not current.hasKey(key):
        return nil
      current = current[key]
    of JArray:
      if segment.kind != JInt:
        return nil
      let idx = segment.getInt()
      if idx < 0 or idx >= current.len:
        return nil
      current = current[idx]
    else:
      return nil
  current

proc getAtPath(root: JsonNode; path: seq[JsonNode]): tuple[ok: bool, value: JsonNode, message: string] =
  let value = tryGetAtPath(root, path)
  if value.isNil:
    return (false, nil, "path not found: " & path.mapIt(segmentLabel(it)).join("."))
  (true, value.copy(), "")

proc ensureObjectPath(root: JsonNode; path: seq[JsonNode]): tuple[ok: bool, value: JsonNode, message: string] =
  var current = root
  for i, segment in path:
    let isLast = i == path.high
    case current.kind
    of JObject:
      if segment.kind != JString:
        return (false, nil, "object paths require string segments")
      let key = segment.getStr()
      if isLast:
        if not current.hasKey(key):
          current[key] = newJObject()
        return (true, current[key], "")
      if not current.hasKey(key):
        let nextSegment = path[i + 1]
        current[key] = if nextSegment.kind == JInt: newJArray() else: newJObject()
      current = current[key]
    of JArray:
      if segment.kind != JInt:
        return (false, nil, "array paths require integer segments")
      let idx = segment.getInt()
      if idx < 0 or idx >= current.len:
        return (false, nil, "array index out of range: " & $idx)
      if isLast:
        return (true, current[idx], "")
      current = current[idx]
    else:
      return (false, nil, "path crosses a scalar value")
  (true, current, "")

proc setAtPath(root: JsonNode; path: seq[JsonNode]; value: JsonNode): tuple[ok: bool, result: JsonNode, message: string] =
  if path.len == 0:
    return (true, value.copy(), "")
  var updated = root.copy()
  let parentPath = path[0 ..< path.high]
  let finalSegment = path[^1]

  if parentPath.len == 0:
    case updated.kind
    of JObject:
      if finalSegment.kind != JString:
        return (false, nil, "object paths require string segments")
      updated[finalSegment.getStr()] = value.copy()
      return (true, updated, "")
    of JArray:
      if finalSegment.kind != JInt:
        return (false, nil, "array paths require integer segments")
      let idx = finalSegment.getInt()
      if idx < 0 or idx >= updated.len:
        return (false, nil, "array index out of range: " & $idx)
      updated.elems[idx] = value.copy()
      return (true, updated, "")
    else:
      return (false, nil, "set requires an object or array root")

  let parentInfo = ensureObjectPath(updated, parentPath)
  if not parentInfo.ok:
    return (false, nil, parentInfo.message)
  var parent = parentInfo.value

  case parent.kind
  of JObject:
    if finalSegment.kind != JString:
      return (false, nil, "object paths require string segments")
    parent[finalSegment.getStr()] = value.copy()
  of JArray:
    if finalSegment.kind != JInt:
      return (false, nil, "array paths require integer segments")
    let idx = finalSegment.getInt()
    if idx < 0 or idx >= parent.len:
      return (false, nil, "array index out of range: " & $idx)
    parent.elems[idx] = value.copy()
  else:
    return (false, nil, "path crosses a scalar value")

  (true, updated, "")

proc deleteAtPath(root: JsonNode; path: seq[JsonNode]): tuple[ok: bool, result: JsonNode, message: string] =
  if path.len == 0:
    return (true, newJNull(), "")

  var updated = root.copy()
  let parentPath = path[0 ..< path.high]
  let finalSegment = path[^1]

  if parentPath.len == 0:
    case updated.kind
    of JObject:
      if finalSegment.kind != JString:
        return (false, nil, "object paths require string segments")
      let key = finalSegment.getStr()
      if updated.hasKey(key):
        updated.delete(key)
      return (true, updated, "")
    of JArray:
      if finalSegment.kind != JInt:
        return (false, nil, "array paths require integer segments")
      let idx = finalSegment.getInt()
      if idx < 0 or idx >= updated.len:
        return (false, nil, "array index out of range: " & $idx)
      updated.elems.delete(idx)
      return (true, updated, "")
    else:
      return (false, nil, "delete requires an object or array root")

  let parentInfo = ensureObjectPath(updated, parentPath)
  if not parentInfo.ok:
    return (false, nil, parentInfo.message)
  var parent = parentInfo.value

  case parent.kind
  of JObject:
    if finalSegment.kind != JString:
      return (false, nil, "object paths require string segments")
    let key = finalSegment.getStr()
    if parent.hasKey(key):
      parent.delete(key)
  of JArray:
    if finalSegment.kind != JInt:
      return (false, nil, "array paths require integer segments")
    let idx = finalSegment.getInt()
    if idx < 0 or idx >= parent.len:
      return (false, nil, "array index out of range: " & $idx)
    parent.elems.delete(idx)
  else:
    return (false, nil, "path crosses a scalar value")

  (true, updated, "")

proc deepMerge(base, patch: JsonNode): JsonNode =
  if base.isNil:
    return if patch.isNil: newJNull() else: patch.copy()
  if patch.isNil:
    return base.copy()
  if base.kind == JObject and patch.kind == JObject:
    result = base.copy()
    for key, value in patch:
      if result.hasKey(key):
        result[key] = deepMerge(result[key], value)
      else:
        result[key] = value.copy()
  else:
    result = patch.copy()

proc parseFilter(node: JsonNode): tuple[ok: bool, spec: TableFilterSpec, message: string] =
  if node.isNil or node.kind != JObject:
    return (false, default(TableFilterSpec), "where clauses must be objects")
  let fieldInfo = parsePathNode(node{"field"}, "where.field")
  if not fieldInfo.ok:
    return (false, default(TableFilterSpec), fieldInfo.message)
  let opName = node{"op"}.getStr("eq").toLowerAscii()
  let valueNode =
    if node.hasKey("value"): node["value"].copy()
    else: newJNull()
  (true, TableFilterSpec(fieldPath: fieldInfo.path, op: opName, value: valueNode), "")

proc parseSortSpec(node: JsonNode): tuple[ok: bool, spec: TableSortSpec, message: string] =
  if node.isNil or node.kind != JObject:
    return (false, default(TableSortSpec), "sort clauses must be objects")
  let fieldInfo = parsePathNode(node{"field"}, "sort.field")
  if not fieldInfo.ok:
    return (false, default(TableSortSpec), fieldInfo.message)
  let order = node{"order"}.getStr("asc").toLowerAscii()
  let sortOrder =
    case order
    of "asc": soAsc
    of "desc": soDesc
    else: return (false, default(TableSortSpec), "sort.order must be 'asc' or 'desc'")
  (true, TableSortSpec(fieldPath: fieldInfo.path, order: sortOrder), "")

proc fieldAlias(node: JsonNode): string =
  case node.kind
  of JString:
    node.getStr()
  of JInt:
    $node.getInt()
  of JArray:
    var parts: seq[string] = @[]
    for segment in node:
      parts.add(segmentLabel(segment))
    parts.join(".")
  else:
    "field"

proc rowMatches(row: JsonNode; spec: TableFilterSpec): bool =
  let actual = tryGetAtPath(row, spec.fieldPath)
  case spec.op
  of "exists":
    not actual.isNil
  of "eq":
    jsonNodesEqual(actual, spec.value)
  of "ne":
    not jsonNodesEqual(actual, spec.value)
  of "gt":
    compareJsonNodes(actual, spec.value) > 0
  of "gte":
    compareJsonNodes(actual, spec.value) >= 0
  of "lt":
    compareJsonNodes(actual, spec.value) < 0
  of "lte":
    compareJsonNodes(actual, spec.value) <= 0
  of "contains":
    if actual.isNil:
      false
    elif actual.kind == JString and spec.value.kind == JString:
      actual.getStr().contains(spec.value.getStr())
    elif actual.kind == JArray:
      actual.elems.anyIt(jsonNodesEqual(it, spec.value))
    else:
      false
  else:
    false

proc projectRow(row: JsonNode; selectFields: seq[JsonNode]): JsonNode =
  if selectFields.len == 0:
    return row.copy()
  result = newJObject()
  if row.isNil or row.kind != JObject:
    return row.copy()
  for field in selectFields:
    let fieldInfo = parsePathNode(field, "select")
    if not fieldInfo.ok:
      continue
    let value = tryGetAtPath(row, fieldInfo.path)
    if not value.isNil:
      result[fieldAlias(field)] = value.copy()

proc detectRowsArray(inputNode: JsonNode): tuple[ok: bool, rows: JsonNode, message: string] =
  if inputNode.isNil:
    return (false, nil, "input is required")
  if inputNode.kind == JArray:
    return (true, inputNode, "")
  if inputNode.kind != JObject:
    return (false, nil, "input must be an array or object")

  let candidatePaths = [
    @[%*"data", %*"rows"],
    @[%*"data", %*"items"],
    @[%*"data", %*"matches"],
    @[%*"data", %*"lines"],
    @[%*"rows"],
    @[%*"items"],
    @[%*"matches"],
    @[%*"lines"],
  ]
  for path in candidatePaths:
    let value = tryGetAtPath(inputNode, path)
    if not value.isNil and value.kind == JArray:
      return (true, value, "")
  (false, nil, "could not detect rows array in input")

proc runJsonQuery*(request: JsonNode): StructuredToolResult =
  if request.isNil or request.kind != JObject:
    return usageErrorToolResult("json_query request must be an object")
  if not request.hasKey("op"):
    return usageErrorToolResult("op is required")
  if not request.hasKey("input"):
    return usageErrorToolResult("input is required")

  let opName = request["op"].getStr("").toLowerAscii()
  let inputNode = request["input"]

  case opName
  of "get":
    let pathInfo = parsePathNode(request{"path"}, "path")
    if not pathInfo.ok:
      return usageErrorToolResult(pathInfo.message)
    let lookup = getAtPath(inputNode, pathInfo.path)
    if not lookup.ok:
      return usageErrorToolResult(lookup.message)
    successToolResult(%*{"value": lookup.value})
  of "set":
    let pathInfo = parsePathNode(request{"path"}, "path")
    if not pathInfo.ok:
      return usageErrorToolResult(pathInfo.message)
    if not request.hasKey("value"):
      return usageErrorToolResult("value is required for set")
    let updated = setAtPath(inputNode, pathInfo.path, request["value"])
    if not updated.ok:
      return usageErrorToolResult(updated.message)
    successToolResult(%*{"value": updated.result})
  of "delete":
    let pathInfo = parsePathNode(request{"path"}, "path")
    if not pathInfo.ok:
      return usageErrorToolResult(pathInfo.message)
    let updated = deleteAtPath(inputNode, pathInfo.path)
    if not updated.ok:
      return usageErrorToolResult(updated.message)
    successToolResult(%*{"value": updated.result})
  of "merge":
    if not request.hasKey("patch"):
      return usageErrorToolResult("patch is required for merge")
    successToolResult(%*{"value": deepMerge(inputNode, request["patch"])})
  else:
    usageErrorToolResult("unsupported json_query op: " & opName)

proc runTableQuery*(request: JsonNode): StructuredToolResult =
  if request.isNil or request.kind != JObject:
    return usageErrorToolResult("table_query request must be an object")
  let rowsSource: tuple[ok: bool, rows: JsonNode, message: string] =
    if request.hasKey("rows"):
      if request["rows"].kind != JArray:
        return usageErrorToolResult("rows must be an array")
      (true, request["rows"], "")
    elif request.hasKey("input"):
      if request.hasKey("rows_path"):
        let pathInfo = parsePathNode(request["rows_path"], "rows_path")
        if not pathInfo.ok:
          return usageErrorToolResult(pathInfo.message)
        let rowsNode = tryGetAtPath(request["input"], pathInfo.path)
        if rowsNode.isNil:
          return usageErrorToolResult("rows_path not found")
        if rowsNode.kind != JArray:
          return usageErrorToolResult("rows_path must resolve to an array")
        (true, rowsNode, "")
      else:
        detectRowsArray(request["input"])
    else:
      (false, nil, "rows or input is required")
  if not rowsSource.ok:
    return usageErrorToolResult(rowsSource.message)

  var rows: seq[JsonNode] = @[]
  for row in rowsSource.rows:
    rows.add(row.copy())

  if request.hasKey("where"):
    if request["where"].kind != JArray:
      return usageErrorToolResult("where must be an array")
    var filters: seq[TableFilterSpec] = @[]
    for clause in request["where"]:
      let filterInfo = parseFilter(clause)
      if not filterInfo.ok:
        return usageErrorToolResult(filterInfo.message)
      filters.add(filterInfo.spec)
    rows = rows.filterIt:
      var keep = true
      for filterSpec in filters:
        if not rowMatches(it, filterSpec):
          keep = false
          break
      keep

  if request.hasKey("sort"):
    if request["sort"].kind != JArray:
      return usageErrorToolResult("sort must be an array")
    var sortSpecs: seq[TableSortSpec] = @[]
    for specNode in request["sort"]:
      let specInfo = parseSortSpec(specNode)
      if not specInfo.ok:
        return usageErrorToolResult(specInfo.message)
      sortSpecs.add(specInfo.spec)
    rows.sort(proc(a, b: JsonNode): int =
      for spec in sortSpecs:
        let cmpValue = compareJsonNodes(tryGetAtPath(a, spec.fieldPath), tryGetAtPath(b, spec.fieldPath))
        if cmpValue != 0:
          return if spec.order == soAsc: cmpValue else: -cmpValue
      0
    )

  var selectFields: seq[JsonNode] = @[]
  if request.hasKey("select"):
    if request["select"].kind != JArray:
      return usageErrorToolResult("select must be an array")
    for field in request["select"]:
      if field.kind notin {JString, JInt, JArray}:
        return usageErrorToolResult("select fields must be strings, integers, or path arrays")
      selectFields.add(field.copy())

  var outputRows: seq[JsonNode] = @[]
  for row in rows:
    outputRows.add(projectRow(row, selectFields))

  if request.hasKey("limit"):
    let limitValue = request["limit"]
    if limitValue.kind != JInt:
      return usageErrorToolResult("limit must be an integer")
    let limit = limitValue.getInt()
    if limit < 0:
      return usageErrorToolResult("limit must be >= 0")
    if outputRows.len > limit:
      outputRows.setLen(limit)

  successToolResult(%*{"rows": outputRows})
