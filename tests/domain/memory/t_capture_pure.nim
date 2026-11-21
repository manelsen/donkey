import std/[strutils, unicode, unittest]
import donkey/domain/memory/capture_pure

proc runTests*() =
  suite "auto memory capture policy":

    test "short correction is captured":
      check not shouldSkipAutoMemoryCapture("Não, o prazo é sexta", "Anotado: sexta.")
      check not shouldSkipAutoMemoryCapture("era o outro arquivo", "Certo, troquei.")

    test "greetings and bare acknowledgements are skipped":
      for text in ["Oi", "oi!", "Olá", "ok", "Ok.", "Obrigado!", "valeu 😊",
                   "bom dia", "thanks", "hello", "  blz  ", "👍"]:
        check shouldSkipAutoMemoryCapture(text, "Olá! Em que posso ajudar?")

    test "greeting followed by content is captured":
      check not shouldSkipAutoMemoryCapture("Oi, o prazo mudou pra sexta", "Anotado.")

    test "empty sides are skipped":
      check shouldSkipAutoMemoryCapture("", "resposta")
      check shouldSkipAutoMemoryCapture("   ", "resposta")
      check shouldSkipAutoMemoryCapture("uma pergunta qualquer do usuario", "  ")

    test "slash commands are skipped":
      check shouldSkipAutoMemoryCapture("/models", "Modelo definido.")

    test "operational failures are skipped":
      check shouldSkipAutoMemoryCapture(
        "leia o arquivo de configuracao por favor", "Error: file not found")
      check shouldSkipAutoMemoryCapture(
        "leia o arquivo de configuracao por favor",
        "Desculpe, ocorreu um erro: timeout")
      check shouldSkipAutoMemoryCapture(
        "pesquise isso na web para mim agora", "Não consigo acessar a web agora.")

    test "substantive turn is captured":
      check not shouldSkipAutoMemoryCapture(
        "Prefiro respostas curtas e sem elogio.", "Combinado, sem elogio.")

    test "clip keeps short text and marks truncation on long text":
      check clipAutoMemoryCapture("  curto  ") == "curto"
      let clipped = clipAutoMemoryCapture(repeat("a", AutoMemoryCaptureMaxChars + 50))
      check clipped.len <= AutoMemoryCaptureMaxChars
      check clipped.endsWith("[…truncated]")

    test "clip never splits a UTF-8 code point":
      let clipped = clipAutoMemoryCapture(repeat("ação ", AutoMemoryCaptureMaxChars))
      let body = clipped[0 ..< clipped.len - "\n[…truncated]".len]
      check validateUtf8(body) == -1

    test "entry keeps both voices":
      let entry = formatAutoMemoryEntry("pergunta", "resposta")
      check entry == "- **User:** pergunta\n  **Response:** resposta\n"

when isMainModule:
  runTests()
