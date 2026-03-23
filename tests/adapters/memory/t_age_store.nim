## Tests for AgeStoreAdapter — pure functions and contract tests.
##
## Compile with -d:withPostgres to activate integration tests.
## Unit tests for pure functions (sanitizeTextForCypher, stripAgtpeValue, etc.) run always.
## Requires PostgreSQL with Apache AGE extension installed for integration tests.
## Environment: POSTGRES_DSN must be set for integration tests.

import std/[strutils, unittest]
import donkey/core/types
import donkey/core/pipeops
import donkey/domain/memory/graph_pure
import donkey/adapters/memory/age_store

# ── Pure function unit tests (always available) ────────────────────────────────

suite "AgeStoreAdapter pure functions":
  test "sanitizeTextForCypher: escapes single quotes":
    let input = "hello 'world'"
    let result = sanitizeTextForCypher(input)
    check result == "hello \\'world\\'"

  test "sanitizeTextForCypher: truncates long strings":
    let input = "x".repeat(300)
    let result = sanitizeTextForCypher(input, maxLen = 50)
    check result.len == 50

  test "sanitizeTextForCypher: handles empty string":
    let result = sanitizeTextForCypher("")
    check result == ""

  test "sanitizeTextForCypher: maxLen parameter":
    let input = "hello world"
    let result = sanitizeTextForCypher(input, maxLen = 5)
    check result == "hello"

  test "stripAgtpeValue: removes quotes":
    check stripAgtpeValue("\"hello\"") == "hello"
    check stripAgtpeValue("\"\"hello\"\"") == "hello"

  test "stripAgtpeValue: handles no quotes":
    check stripAgtpeValue("hello") == "hello"

  test "stripAgtpeValue: strips spaces":
    check stripAgtpeValue("  \"hello\"  ") == "hello"

  test "isValidNodeLabel: valid labels return true":
    check isValidNodeLabel("Person")
    check isValidNodeLabel("Memory")
    check isValidNodeLabel("Concept")
    check isValidNodeLabel("Fact")

  test "isValidNodeLabel: invalid labels return false":
    check not isValidNodeLabel("InvalidLabel")
    check not isValidNodeLabel("")
    check not isValidNodeLabel("person")

  test "isValidEdgeLabel: valid labels return true":
    check isValidEdgeLabel("KNOWS")
    check isValidEdgeLabel("ABOUT")
    check isValidEdgeLabel("MENTIONS")

  test "isValidEdgeLabel: invalid labels return false":
    check not isValidEdgeLabel("INVALID_EDGE")
    check not isValidEdgeLabel("")
    check not isValidEdgeLabel("knows")

  test "DefaultGraphName is set correctly":
    check DefaultGraphName == "donkey_graph"

  test "AgeNodeLabels contains expected labels":
    check "Person" in AgeNodeLabels
    check "Memory" in AgeNodeLabels
    check "Concept" in AgeNodeLabels
    check "Fact" in AgeNodeLabels

  test "AgeEdgeLabels contains expected labels":
    check "KNOWS" in AgeEdgeLabels
    check "ABOUT" in AgeEdgeLabels
    check "MENTIONS" in AgeEdgeLabels

  test "triplesToCypherNodes: generates MERGE statements":
    let triples = @[
      buildTriple("alice", "knows", "bob", "alice knows bob", 0.9),
      buildTriple("alice", "likes", "charlie", "alice likes charlie", 0.8),
    ]
    let userId = UserId("test-user")
    let cypher = triplesToCypherNodes(triples, userId, "Person")
    # Check that MERGE statements are generated for subjects and objects
    check cypher.contains("MERGE (s_")
    check cypher.contains("MERGE (o_")
    # Check subject label is lowercased, object label is Memory (capital M)
    check cypher.contains(":person")
    check cypher.contains(":Memory")
    # Check user_id is included
    check cypher.contains("user_id: 'test-user'")

  test "triplesToCypherNodes: deduplicates subjects":
    let triples = @[
      buildTriple("alice", "knows", "bob", "alice knows bob", 0.9),
      buildTriple("alice", "likes", "charlie", "alice likes charlie", 0.8),
    ]
    let userId = UserId("test-user")
    let cypher = triplesToCypherNodes(triples, userId, "Person")
    # Should only have one MERGE for alice (subject of both triples)
    check cypher.count("MERGE (s_1:person") == 1

  test "triplesToCypherEdges: generates CREATE statements":
    let triples = @[
      buildTriple("alice", "knows", "bob", "alice knows bob", 0.9),
    ]
    let userId = UserId("test-user")
    let cypher = triplesToCypherEdges(triples, userId, "Person")
    check cypher.contains("CREATE (s_1)-[:KNOWS")
    check cypher.contains("->(o_1)")

  test "triplesToCypherEdges: uses RELATES_TO for unknown edge labels":
    let triples = @[
      buildTriple("alice", "works with", "bob", "alice works with bob", 0.7),
    ]
    let userId = UserId("test-user")
    let cypher = triplesToCypherEdges(triples, userId, "Person")
    # "works with" becomes WORKS_WITH which is not in AgeEdgeLabels, so RELATES_TO is used
    check cypher.contains("RELATES_TO")
    check cypher.contains("predicate: 'works with'")

  test "buildTriple: creates valid triple":
    let t = buildTriple("alice", "knows", "bob", "alice knows bob", 0.9)
    check t.subject == "alice"
    check t.predicate == "knows"
    check t.obj == "bob"
    check t.confidence == 0.9
    check t.rawText == "alice knows bob"

  test "buildTriple: normalizes entities":
    let t = buildTriple("  ALICE  ", "KNOWS", "  bob  ", "ALICE KNOWS bob", 0.9)
    check t.subject == "alice"
    check t.predicate == "knows"
    check t.obj == "bob"

# ── Constructor tests ─────────────────────────────────────────────────────────

when defined(withPostgres):
  import db_connector/db_postgres

  const
    TestGraphName = "donkey_test_graph"
    TestUserId = UserId("test-user-age")
    TestDsn = "postgres:postgres@localhost/postgres"

  suite "AgeStoreAdapter constructor":
    test "newAgeStoreAdapter: creates adapter with defaults":
      let adapter = newAgeStoreAdapter("dsn")
      check adapter.dsn == "dsn"
      check adapter.graphName == DefaultGraphName

    test "newAgeStoreAdapter: creates adapter with custom graph name":
      let adapter = newAgeStoreAdapter("dsn", "custom_graph")
      check adapter.dsn == "dsn"
      check adapter.graphName == "custom_graph"

  # ── Integration tests ─────────────────────────────────────────────────────────

  when defined(INTEGRATION):
    let dsn = getEnv("POSTGRES_DSN", TestDsn)
    let adapter = newAgeStoreAdapter(dsn, TestGraphName)

    proc runContractTests(a: AgeStoreAdapter) =
      let uid = TestUserId

      suite "AgeStoreAdapter contract [" & a.graphName & "]":

        test "initGraph: creates graph":
          let r = a.initGraph()
          check r.isOk

        test "countNodes: returns zero for absent user":
          let r = a.countNodes(uid, "Person")
          check r.isOk
          check r.get == 0

        test "upsertPerson: creates a Person node":
          let r = a.upsertPerson(uid, "alice")
          check r.isOk
          check r.get.len > 0

        test "countNodes: returns one after upsertPerson":
          discard a.upsertPerson(uid, "bob")
          let r = a.countNodes(uid, "Person")
          check r.isOk
          check r.get >= 1

        test "queryNodes: returns nodes after upsertPerson":
          discard a.upsertPerson(uid, "charlie")
          let r = a.queryNodes(uid, "Person")
          check r.isOk
          check r.get.len >= 1

        test "storeTriple: stores a triple":
          let triple = buildTriple("dave", "knows", "eve", "dave knows eve", 0.9)
          let r = a.storeTriple(uid, triple, "Person")
          check r.isOk

        test "storeTriples: stores multiple triples and returns count":
          let triples = @[
            buildTriple("frank", "works with", "grace", "frank works with grace", 0.8),
            buildTriple("frank", "likes", "helen", "frank likes helen", 0.7),
          ]
          let r = a.storeTriples(uid, triples, "Person")
          check r.isOk
          check r.get == 2

        test "linkPersons: creates edge between two persons":
          discard a.upsertPerson(uid, "ivan")
          discard a.upsertPerson(uid, "julia")
          let r = a.linkPersons(uid, "ivan", "julia", "KNOWS")
          check r.isOk

        test "upsertSession: creates a Session node":
          let r = a.upsertSession(uid, "session-123")
          check r.isOk

        test "linkSessions: creates CONTINUED_IN edge":
          discard a.upsertSession(uid, "session-001")
          discard a.upsertSession(uid, "session-002")
          let r = a.linkSessions(uid, "session-001", "session-002")
          check r.isOk

        test "addFact: creates a Fact node":
          let r = a.addFact(uid, "gravity exists", "physics")
          check r.isOk

        test "addFact without concept: creates a Fact node":
          let r = a.addFact(uid, "the sky is blue")
          check r.isOk

        test "addMemory: creates a Memory node":
          let r = a.addMemory(uid, "remember this moment")
          check r.isOk

        test "findRelatedConcepts: finds related nodes":
          discard a.addFact(uid, "water boils at 100c", "chemistry")
          let r = a.findRelatedConcepts(uid, "chemistry")
          check r.isOk

        test "traverseFromNode: traverses graph":
          let r = a.traverseFromNode(uid, "Person", "name", "alice", "KNOWS", 1)
          check r.isOk

        test "deleteNode: removes a node":
          discard a.upsertPerson(uid, "to-delete")
          let r = a.deleteNode(uid, "Person", "name", "to-delete")
          check r.isOk

        test "clearUserGraph: removes all user nodes and edges":
          discard a.upsertPerson(uid, "person-1")
          discard a.upsertPerson(uid, "person-2")
          let r = a.clearUserGraph(uid)
          check r.isOk
          # After clear, count should be 0
          let countR = a.countNodes(uid, "Person")
          check countR.isOk
          check countR.get == 0

    # Run integration tests
    echo "Running AgeStoreAdapter integration tests..."
    echo "Note: Requires PostgreSQL with Apache AGE extension."
    echo "Set POSTGRES_DSN environment variable to run."
    runContractTests(adapter)

    # Cleanup
    discard adapter.clearUserGraph(TestUserId)
