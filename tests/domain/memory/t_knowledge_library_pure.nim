import std/[unittest, sequtils, strutils]
import donkey/domain/memory/knowledge_library_pure

suite "knowledge_library_pure":

  test "collection membership and ACL filter accessible chunks by agent":
    let shared = newKnowledgeCollection("shared-ops", "Ops", @["agent-alpha", "agent-beta"])
    let private = newKnowledgeCollection("private-finance", "Finance", @["agent-alpha"])
    let sharedDoc = newKnowledgeDocument("doc-ops", shared.id, "Incident handbook", "application/pdf")
    let privateDoc = newKnowledgeDocument("doc-fin", private.id, "Payroll", "application/pdf")
    let chunks = @[
      newKnowledgeChunk("chunk-ops", sharedDoc, 0, "Escalate incidents through the retry dashboard."),
      newKnowledgeChunk("chunk-fin", privateDoc, 0, "Payroll closes on the last business day."),
    ]
    let alphaHits = accessibleChunks("agent-alpha", @[shared, private], chunks)
    let betaHits = accessibleChunks("agent-beta", @[shared, private], chunks)
    check alphaHits.len == 2
    check betaHits.len == 1
    check betaHits[0].id == "chunk-ops"

  test "ingestPdfDocument chunks extracted text and preserves document metadata":
    let collection = newKnowledgeCollection("shared-ops", "Ops", @["agent-alpha"])
    let ingestion = ingestPdfDocument(
      collection = collection,
      documentId = "pdf-ops",
      title = "Incident handbook",
      extractedText = "Retry dashboards first.\nEscalate incidents after confirming amplification.\nCollect before-and-after graphs.",
      chunkSize = 40,
    )
    check ingestion.document.id == "pdf-ops"
    check ingestion.document.collectionId == collection.id
    check ingestion.chunks.len >= 2
    check ingestion.chunks[0].documentId == "pdf-ops"
    check ingestion.chunks.allIt(it.collectionId == collection.id)

  test "ingestDocxDocument preserves ordered text chunks":
    let collection = newKnowledgeCollection("shared-ops", "Ops", @["agent-alpha"])
    let ingestion = ingestDocxDocument(
      collection = collection,
      documentId = "docx-ops",
      title = "Runbook",
      extractedText = "Step one.\nStep two.\nStep three.",
      chunkSize = 20,
    )
    check ingestion.document.mimeType ==
      "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
    check ingestion.chunks.len >= 2
    check ingestion.chunks[0].text.contains("Step one")

  test "ingestXlsxDocument keeps sheet-aware chunks":
    let collection = newKnowledgeCollection("shared-finance", "Finance", @["agent-alpha"])
    let ingestion = ingestXlsxDocument(
      collection = collection,
      documentId = "xlsx-fin",
      title = "Budget workbook",
      sheets = @[("Q1", "Revenue 10\nCost 4"), ("Q2", "Revenue 12\nCost 5")],
      chunkSize = 18,
    )
    check ingestion.document.mimeType ==
      "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    check ingestion.chunks.len >= 2
    check ingestion.chunks.anyIt(it.sheetName == "Q1")
    check ingestion.chunks.anyIt(it.sheetName == "Q2")

  test "searchKnowledgeLibrary filters by ACL and combines explicitly with autobiographical memory":
    let shared = newKnowledgeCollection("shared-ops", "Ops", @["agent-alpha"])
    let private = newKnowledgeCollection("private-fin", "Finance", @["agent-owner"])
    let sharedDoc = newKnowledgeDocument("doc-ops", shared.id, "Incident handbook", "application/pdf")
    let privateDoc = newKnowledgeDocument("doc-fin", private.id, "Payroll", "application/pdf")
    let docs = @[sharedDoc, privateDoc]
    let chunks = @[
      newKnowledgeChunk("chunk-ops", sharedDoc, 0, "Retry amplification should be checked before raising timeouts."),
      newKnowledgeChunk("chunk-fin", privateDoc, 0, "Payroll closes on the last business day."),
    ]
    let hits = searchKnowledgeLibrary(
      query = "retry timeouts",
      agentId = "agent-alpha",
      collections = @[shared, private],
      documents = docs,
      chunks = chunks,
      limit = 3,
    )
    check hits.len == 1
    check hits[0].chunk.id == "chunk-ops"
    let context = buildMixedRetrievalContext(
      autobiographicalMemories = @["User debugged retry amplification yesterday."],
      knowledgeHits = hits,
    )
    check context.contains("Relevant memories:")
    check context.contains("Knowledge library:")
    check context.contains("Incident handbook")
    check "Payroll" notin context
