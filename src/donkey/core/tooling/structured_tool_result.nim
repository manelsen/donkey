## Stable JSON envelope for structured native tool outputs.

import std/json
import ../../domain/message

const
  structuredToolContractVersion* = "donkey.native_tool/v1"

type
  StructuredToolResult* = object
    kind*: ToolResultKind
    data*: JsonNode
    errorMessage*: string

func successToolResult*(payload: JsonNode): StructuredToolResult =
  StructuredToolResult(kind: trkOutput, data: payload)

func usageErrorToolResult*(message: string): StructuredToolResult =
  StructuredToolResult(kind: trkUsageError, errorMessage: message)

func operationalErrorToolResult*(message: string): StructuredToolResult =
  StructuredToolResult(kind: trkOperationalError, errorMessage: message)

func toNode*(value: StructuredToolResult): JsonNode =
  result = %*{
    "ok": value.kind == trkOutput,
    "status": toolResultKindLabel(value.kind),
    "contract": structuredToolContractVersion,
  }

  case value.kind
  of trkOutput:
    result["data"] = value.data
  of trkUsageError, trkOperationalError:
    result["error"] = %*{"message": value.errorMessage}

func toJson*(value: StructuredToolResult): string =
  $value.toNode()
