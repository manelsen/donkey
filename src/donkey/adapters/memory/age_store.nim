## age_store.nim — Apache AGE Graph Adapter.
##
## Execute Cypher queries against PostgreSQL with Apache AGE extension.
## Compile with -d:withPostgres to activate (links libpq).
## Without the flag the module exports only a stub type and pure helpers.
##
## Schema (created on init):
##   Apache AGE graph "donkey_graph" with labels:
##     Person, Memory, Fact, Concept, Solution, ErrorPattern, Session, Task, Preference, Document
##   Edges:
##     MENTIONS, ABOUT, FROM, RESOLVES, USES, CONTINUED_IN, KNOWS,
##     HAS_PREFERENCE, IS_CHILD_OF, IS_PARENT_OF
##
## All I/O is fallible (database can fail) and returns Result[T, string].
## Operations are chained via >>= (railway-oriented programming).
##
## Usage example:
##   adapter.initGraph().valueOr:
##     log.error("init: " & error)
##   let triples = text |> extractTriples
##   triples |> storeTriples(adapter, userId).valueOr:
##     log.error("store: " & error)

import std/[strutils]

import ../../core/pipeops
import ../../core/types
import ../../domain/memory/graph_pure

# ── Constants ─────────────────────────────────────────────────────────────────

const
  DefaultGraphName* = "donkey_graph"
    ## Default AGE graph name.

  AgeNodeLabels* = [
    "Person", "Memory", "Fact", "Concept", "Solution",
    "ErrorPattern", "Session", "Task", "Preference", "Document"
  ]
    ## Valid AGE node labels.

  AgeEdgeLabels* = [
    "MENTIONS", "ABOUT", "FROM", "RESOLVES", "USES", "CONTINUED_IN",
    "KNOWS", "HAS_PREFERENCE", "IS_CHILD_OF", "IS_PARENT_OF"
  ]
    ## Valid AGE edge labels.

# ── Pure helpers (always available) ───────────────────────────────────────────

func sanitizeTextForCypher*(text: string; maxLen = 200): string =
  ## Escapes single quotes and truncates for safe Cypher injection.
  result = text.replace("'", "\\'")
  if result.len > maxLen:
    result = result[0 ..< maxLen]

func stripAgtpeValue*(value: string): string =
  ## Strips agtype string delimiters from AGE return values.
  value.strip(chars = {'"', ' '})

func isValidNodeLabel*(label: string): bool =
  ## Checks if a label is in the allowed set.
  label in AgeNodeLabels

func isValidEdgeLabel*(label: string): bool =
  ## Checks if an edge label is in the allowed set.
  label in AgeEdgeLabels

func triplesToCypherNodes*(
  triples: seq[TripleText];
  userId: UserId;
  nodeLabel = "Concept"
): string =
  ## Generates Cypher MERGE statements for triple subjects and objects.
  ## Subjects become nodes of the given label; objects become Memory nodes.
  var seen: seq[string]
  for t in triples:
    let subKey = t.subject & ":" & nodeLabel
    if subKey notin seen:
      seen.add(subKey)
      let safeSub = sanitizeTextForCypher(t.subject)
      let safeLabel = nodeLabel.toLowerAscii()
      result &= "MERGE (s_" & $seen.len & ":" & safeLabel & " {name: '" & safeSub &
                 "', user_id: '" & $userId & "'})\n"
    let objKey = t.obj & ":Memory"
    if objKey notin seen:
      seen.add(objKey)
      let safeObj = sanitizeTextForCypher(t.obj)
      result &= "MERGE (o_" & $seen.len & ":Memory {name: '" & safeObj &
                 "', user_id: '" & $userId & "'})\n"

func triplesToCypherEdges*(
  triples: seq[TripleText];
  userId: UserId;
  subjectLabel = "Concept"
): string =
  ## Generates Cypher CREATE statements for triple edges.
  ## Uses index-based matching since subjects/objects may repeat.
  var subjectIdx = 0
  var objectIdx = 0
  var seenSubj: seq[string]
  var seenObj: seq[string]
  for t in triples:
    let subKey = t.subject
    if subKey notin seenSubj:
      inc subjectIdx
      seenSubj.add(subKey)
    let objKey = t.obj
    if objKey notin seenObj:
      inc objectIdx
      seenObj.add(objKey)
    let safePred = t.predicate.replace(" ", "_").toUpperAscii()
    if isValidEdgeLabel(safePred):
      result &= "CREATE (s_" & $subjectIdx & ")-[:" & safePred &
                 " {confidence: " & $t.confidence & "}]->(o_" & $objectIdx & ")\n"
    else:
      result &= "CREATE (s_" & $subjectIdx & ")-[:RELATES_TO " &
                 "{predicate: '" & sanitizeTextForCypher(t.predicate) &
                 "', confidence: " & $t.confidence & "}]->(o_" & $objectIdx & ")\n"

# ── Conditional PostgreSQL + AGE implementation ───────────────────────────────

when defined(withPostgres):
  import db_connector/db_postgres
  import std/[os]

  type
    AgeStoreAdapter* = object
      dsn*:       string
      graphName*: string
        ## AGE graph name (default: "donkey_graph").

  # ── Database helpers ─────────────────────────────────────────────────────────

  proc openDb*(a: AgeStoreAdapter): Result[DbConn, string] =
    ## Opens a fresh connection. Caller must close().
    ## Sets AGE search_path every time (required per connection).
    try:
      let db = open(a.dsn, "", "", "")
      db.exec(sql"SET search_path = ag_catalog, public")
      ok(db)
    except CatchableError as e:
      err("openDb: " & e.msg)

  proc graphExists*(a: AgeStoreAdapter; db: DbConn): bool =
    let rows = db.getAllRows(
      sql"SELECT count(*) FROM ag_catalog.ag_graph WHERE name = $1",
      a.graphName)
    rows.len > 0 and rows[0][0] != "0"

  proc loadAge*(db: DbConn) =
    ## Loads the age extension for the current connection.
    db.exec(sql"LOAD 'age'")

  # ── Cypher execution helpers ──────────────────────────────────────────────────

  proc cypher*(
    db: DbConn;
    graphName: string;
    query: string;
    retCols: seq[string] = @[]
  ): Result[seq[Row], string] =
    ## Executes a Cypher query via AGE.
    ## retCols specifies the result column aliases with their agtype types.
    ## Returns rows on success.
    try:
      if retCols.len == 0:
        db.exec(sql("SELECT * FROM cypher('" & graphName &
                    "', $$ " & query & " $$) AS (r agtype)"))
        ok(@[])
      else:
        var cols = ""
        for i, c in retCols:
          if i > 0: cols.add(", ")
          cols.add(c & " agtype")
        let q = "SELECT * FROM cypher('" & graphName & "', $$ " &
                query & " $$) AS (" & cols & ")"
        ok(db.getAllRows(sql(q)))
    except CatchableError as e:
      err("cypher: " & e.msg)

  proc cypherVoid*(
    db: DbConn;
    graphName: string;
    query: string
  ): Result[void, string] =
    ## Executes a Cypher query that doesn't return results.
    try:
      db.exec(sql("SELECT * FROM cypher('" & graphName &
                  "', $$ " & query & " $$) AS (r agtype)"))
      ok()
    except CatchableError as e:
      err("cypherVoid: " & e.msg)

  # ── Graph initialization ───────────────────────────────────────────────────────

  proc initGraph*(a: AgeStoreAdapter): Result[void, string] =
    ## Creates the AGE graph if it doesn't exist. Idempotent.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    try:
      db.loadAge()
      if not a.graphExists(db):
        db.exec(sql("SELECT * FROM ag_catalog.create_graph('" & a.graphName & "')"))
      ok()
    except CatchableError as e:
      err("initGraph: " & e.msg)

  # ── Node operations ───────────────────────────────────────────────────────────

  proc mergeNode*(
    a: AgeStoreAdapter;
    userId: UserId;
    label: string;
    properties: seq[(string, string)]
  ): Result[string, string] =
    ## Creates or merges a node with given label and properties.
    ## Properties is a seq of (key, value) pairs.
    ## Returns the node id as string.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    var propsStr = ""
    for i, (k, v) in properties:
      if i > 0: propsStr.add(", ")
      propsStr.add(k & ": '" & sanitizeTextForCypher(v) & "'")
    propsStr.add(", user_id: '" & $userId & "'")

    let cypherQuery = "MERGE (n:" & label & " {" & propsStr & "}) RETURN id(n)"
    let result = db.cypher(a.graphName, cypherQuery, @["id"])
    if result.isErr:
      return err(result.error)
    let rows = result.get
    if rows.len > 0:
      ok(rows[0][0])
    else:
      ok("")

  proc deleteNode*(
    a: AgeStoreAdapter;
    userId: UserId;
    label: string;
    propertyKey: string;
    propertyValue: string
  ): Result[void, string] =
    ## Deletes nodes matching the given label and property.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    let cypherQuery = "MATCH (n:" & label & " {" & propertyKey & ": '" &
                      sanitizeTextForCypher(propertyValue) &
                      "', user_id: '" & $userId & "'}) DETACH DELETE n"
    db.cypherVoid(a.graphName, cypherQuery)

  # ── Edge operations ───────────────────────────────────────────────────────────

  proc createEdge*(
    a: AgeStoreAdapter;
    userId: UserId;
    fromLabel: string;
    fromPropertyKey: string;
    fromPropertyValue: string;
    toLabel: string;
    toPropertyKey: string;
    toPropertyValue: string;
    edgeLabel: string;
    properties: seq[(string, string)] = @[]
  ): Result[string, string] =
    ## Creates a directed edge between two nodes.
    ## Returns the edge id.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    var propsStr = ""
    for i, (k, v) in properties:
      if i > 0: propsStr.add(", ")
      propsStr.add(k & ": '" & sanitizeTextForCypher(v) & "'")

    let cypherQuery = "MATCH (from:" & fromLabel & " {" & fromPropertyKey & ": '" &
                      sanitizeTextForCypher(fromPropertyValue) &
                      "', user_id: '" & $userId & "'}), " &
                      "MATCH (to:" & toLabel & " {" & toPropertyKey & ": '" &
                      sanitizeTextForCypher(toPropertyValue) &
                      "', user_id: '" & $userId & "'}) " &
                      "CREATE (from)-[r:" & edgeLabel &
                      (if propsStr.len > 0: " {" & propsStr & "}" else: "") &
                      "]->(to) RETURN id(r)"
    let result = db.cypher(a.graphName, cypherQuery, @["id"])
    if result.isErr:
      return err(result.error)
    let rows = result.get
    if rows.len > 0:
      ok(rows[0][0])
    else:
      ok("")

  # ── Triple storage ───────────────────────────────────────────────────────────

  proc storeTriple*(
    a: AgeStoreAdapter;
    userId: UserId;
    triple: TripleText;
    subjectLabel = "Concept"
  ): Result[void, string] =
    ## Stores a single triple as two nodes and an edge.
    ## Subject becomes a node of subjectLabel; object becomes a Memory node.
    ## The predicate becomes the edge label.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    try:
      db.loadAge()
      let safeSubj = sanitizeTextForCypher(triple.subject)
      let safeObj = sanitizeTextForCypher(triple.obj)
      let safePred = triple.predicate.replace(" ", "_").toUpperAscii()
      let edgeLabel = if isValidEdgeLabel(safePred): safePred else: "RELATES_TO"

      let cypherQuery = """
        MERGE (s:""" & subjectLabel & """ {name: '""" & safeSubj &
        """', user_id: '""" & $userId & """'})
        MERGE (o:Memory {name: '""" & safeObj &
        """', user_id: '""" & $userId & """'})
        CREATE (s)-[r:""" & edgeLabel & """ {predicate: '""" &
        sanitizeTextForCypher(triple.predicate) &
        """', confidence: """ & $triple.confidence &
        """}]->(o)
        RETURN id(r)
      """
      discard db.cypher(a.graphName, cypherQuery, @["id"])
      ok()
    except CatchableError as e:
      err("storeTriple: " & e.msg)

  proc storeTriples*(
    a: AgeStoreAdapter;
    userId: UserId;
    triples: seq[TripleText];
    subjectLabel = "Concept"
  ): Result[int, string] =
    ## Stores multiple triples. Returns the count of stored edges.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    try:
      db.loadAge()
      var count = 0
      for t in triples:
        let safeSubj = sanitizeTextForCypher(t.subject)
        let safeObj = sanitizeTextForCypher(t.obj)
        let safePred = t.predicate.replace(" ", "_").toUpperAscii()
        let edgeLabel = if isValidEdgeLabel(safePred): safePred else: "RELATES_TO"

        let cypherQuery = """
          MERGE (s:""" & subjectLabel & """ {name: '""" & safeSubj &
          """', user_id: '""" & $userId & """'})
          MERGE (o:Memory {name: '""" & safeObj &
          """', user_id: '""" & $userId & """'})
          CREATE (s)-[r:""" & edgeLabel & """ {predicate: '""" &
          sanitizeTextForCypher(t.predicate) &
          """', confidence: """ & $t.confidence &
          """}]->(o)
        """
        discard db.cypher(a.graphName, cypherQuery, @["id"])
        inc count
      ok(count)
    except CatchableError as e:
      err("storeTriples: " & e.msg)

  # ── Graph traversal ──────────────────────────────────────────────────────────

  proc traverseFromNode*(
    a: AgeStoreAdapter;
    userId: UserId;
    label: string;
    propertyKey: string;
    propertyValue: string;
    edgeLabel: string;
    depth = 1
  ): Result[seq[string], string] =
    ## Returns content of nodes reachable via edgeLabel from the starting node.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    let cypherQuery = "MATCH (start:" & label & " {" & propertyKey & ": '" &
                      sanitizeTextForCypher(propertyValue) &
                      "', user_id: '" & $userId & "'})" &
                      "-[r:" & edgeLabel & "*1.." & $depth & "]-(related) " &
                      "WHERE related.user_id = '" & $userId & "' " &
                      "RETURN DISTINCT related.name"
    let result = db.cypher(a.graphName, cypherQuery, @["name"])
    if result.isErr:
      return err(result.error)
    var names: seq[string]
    for row in result.get:
      let name = stripAgtpeValue(row[0])
      if name.len > 0 and name != "null":
        names.add(name)
    ok(names)

  proc findRelatedConcepts*(
    a: AgeStoreAdapter;
    userId: UserId;
    conceptName: string;
    depth = 2
  ): Result[seq[string], string] =
    ## Finds concepts related to the given concept via any edge.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    let cypherQuery = "MATCH (c:Concept {name: '" &
                      sanitizeTextForCypher(conceptName) &
                      "', user_id: '" & $userId & "'})" &
                      "-[r]-(related) " &
                      "WHERE related.user_id = '" & $userId & "' " &
                      "RETURN DISTINCT related.name"
    let result = db.cypher(a.graphName, cypherQuery, @["name"])
    if result.isErr:
      return err(result.error)
    var names: seq[string]
    for row in result.get:
      let name = stripAgtpeValue(row[0])
      if name.len > 0 and name != "null":
        names.add(name)
    ok(names)

  # ── Query operations ─────────────────────────────────────────────────────────

  proc queryNodes*(
    a: AgeStoreAdapter;
    userId: UserId;
    label: string;
    limit = 100
  ): Result[seq[(string, string)], string] =
    ## Returns (name, property) pairs for nodes of the given label.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    let cypherQuery = "MATCH (n:" & label & " {user_id: '" & $userId &
                      "'}) RETURN n.name LIMIT " & $limit
    let result = db.cypher(a.graphName, cypherQuery, @["name"])
    if result.isErr:
      return err(result.error)
    var nodes: seq[(string, string)]
    for row in result.get:
      nodes.add((stripAgtpeValue(row[0]), label))
    ok(nodes)

  proc countNodes*(
    a: AgeStoreAdapter;
    userId: UserId;
    label: string
  ): Result[int, string] =
    ## Counts nodes of the given label for a user.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    let cypherQuery = "MATCH (n:" & label & " {user_id: '" & $userId &
                      "'}) RETURN count(n)"
    let result = db.cypher(a.graphName, cypherQuery, @["count"])
    if result.isErr:
      return err(result.error)
    if result.get.len > 0:
      let countStr = stripAgtpeValue(result.get[0][0])
      try:
        ok(parseInt(countStr))
      except:
        ok(0)
    else:
      ok(0)

  # ── Person and session operations ─────────────────────────────────────────────

  proc upsertPerson*(
    a: AgeStoreAdapter;
    userId: UserId;
    name: string;
    properties: seq[(string, string)] = @[]
  ): Result[string, string] =
    ## Creates or updates a Person node.
    var allProps = @[("name", name)]
    allProps.add(properties)
    a.mergeNode(userId, "Person", allProps)

  proc linkPersons*(
    a: AgeStoreAdapter;
    userId: UserId;
    fromPerson: string;
    toPerson: string;
    edgeLabel: string
  ): Result[string, string] =
    ## Links two Person nodes with the given edge label.
    a.createEdge(
      userId,
      "Person", "name", fromPerson,
      "Person", "name", toPerson,
      edgeLabel
    )

  proc upsertSession*(
    a: AgeStoreAdapter;
    userId: UserId;
    sessionId: string;
    properties: seq[(string, string)] = @[]
  ): Result[string, string] =
    ## Creates or updates a Session node.
    var allProps = @[("session_id", sessionId)]
    allProps.add(properties)
    a.mergeNode(userId, "Session", allProps)

  proc linkSessions*(
    a: AgeStoreAdapter;
    userId: UserId;
    prevSessionId: string;
    nextSessionId: string
  ): Result[string, string] =
    ## Links two sessions with CONTINUED_IN edge.
    a.createEdge(
      userId,
      "Session", "session_id", prevSessionId,
      "Session", "session_id", nextSessionId,
      "CONTINUED_IN"
    )

  # ── Fact and concept operations ───────────────────────────────────────────────

  proc addFact*(
    a: AgeStoreAdapter;
    userId: UserId;
    fact: string;
    aboutConcept: string = ""
  ): Result[void, string] =
    ## Adds a Fact node, optionally linked to a Concept via ABOUT.
    let triple = buildTriple(fact, "is", aboutConcept, fact, 0.9)
    let storeResult = a.storeTriple(userId, triple, "Fact")
    if storeResult.isErr:
      return err(storeResult.error)
    if aboutConcept.len > 0:
      let edgeResult = a.createEdge(
        userId,
        "Fact", "name", fact,
        "Concept", "name", aboutConcept,
        "ABOUT"
      )
      if edgeResult.isErr:
        return err(edgeResult.error)
    ok()

  proc addMemory*(
    a: AgeStoreAdapter;
    userId: UserId;
    content: string
  ): Result[void, string] =
    ## Adds a Memory node linked to the user's Person.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    try:
      db.loadAge()
      let cypherQuery = """
        MERGE (u:Person {user_id: '""" & $userId & """', name: 'self'})
        CREATE (m:Memory {content: '""" & sanitizeTextForCypher(content) &
        """', user_id: '""" & $userId & """'})
        CREATE (u)-[:HAS_MEMORY]->(m)
        RETURN id(m)
      """
      discard db.cypher(a.graphName, cypherQuery, @["id"])
      ok()
    except CatchableError as e:
      err("addMemory: " & e.msg)

  # ── Utility ──────────────────────────────────────────────────────────────────

  proc clearUserGraph*(
    a: AgeStoreAdapter;
    userId: UserId
  ): Result[void, string] =
    ## Removes all nodes and edges for a user. Use with caution.
    let openResult = a.openDb
    if openResult.isErr:
      return err(openResult.error)
    let db = openResult.get
    defer: db.close()

    try:
      db.loadAge()
      discard db.cypher(a.graphName,
        "MATCH (n {user_id: '" & $userId & "'}) DETACH DELETE n")
      ok()
    except CatchableError as e:
      err("clearUserGraph: " & e.msg)

  # ── Constructor ─────────────────────────────────────────────────────────────

  proc newAgeStoreAdapter*(
    dsn: string;
    graphName = DefaultGraphName
  ): AgeStoreAdapter =
    AgeStoreAdapter(dsn: dsn, graphName: graphName)

else:
  ## Stub — non-postgres builds import this module without activating any code.
  type AgeStoreAdapter* = object
