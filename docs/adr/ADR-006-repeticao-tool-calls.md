# ADR-006 — Detecção de repetição em tool calls

**Status:** Aceito
**Data:** 2026-03 (F4 revisão)

## Contexto

O orchestrator tem um hard limit de rounds de tool calls para evitar loops infinitos. O limite original era `MaxToolRoundsOrch = 5`. Em produção, modelos entraram em loops com mais de 150 chamadas tentadas antes de atingir o limite — e o limite de 5 interrompia conversas legítimas com múltiplos steps.

## Decisão

Substituir o limite fixo baixo por detecção de repetição baseada em histórico recente, com limite alto como safety net:

```nim
const
  MaxToolRoundsOrch   = 50   ## Hard cap de segurança
  RepeatAbortThreshold = 2   ## Abort se mesmo (tool, args) visto N vezes

var recentCalls: seq[(string, string)]  ## (toolName, inputJson) das últimas chamadas

# Antes de cada tool call:
let key = (call.name, call.inputJson)
let repeatCount = recentCalls.countIt(it == key)
if repeatCount >= RepeatAbortThreshold:
  # Abort: enviar mensagem de erro, encerrar loop
  break
recentCalls.add(key)
```

**Critério de repetição:** mesmo `(toolName, inputJson)` exato. Chamadas com argumentos diferentes não contam. O histórico não é truncado — todas as chamadas da sessão são consideradas.

## Racional

| Abordagem | Problema |
|-----------|----------|
| Limite fixo baixo (5) | Interrompe workflows legítimos com 6+ steps |
| Limite fixo alto (50) | Loop infinito fica 50 iterações antes de abortar |
| **Detecção de repetição + cap alto** | Aborta loops rapidamente; não limita workflows legítimos |

Um modelo em loop geralmente repete a mesma chamada com os mesmos argumentos. A detecção de repetição exata (`inputJson` completo) evita falsos positivos quando o modelo faz a mesma tool com parâmetros diferentes (ex: `bash "ls /tmp"` e `bash "ls /home"` são chamadas diferentes).

## Consequências

- `recentCalls: seq[(string, string)]` cresce durante a sessão — memória negligível para o caso de uso (50 calls máximo).
- Repetição de chamada idêntica que **não** é loop (ex: usuário pede `ls` duas vezes explicitamente) seria abortada na segunda chamada. Aceitável: modelos bem comportados não repetem sem razão; se repetirem, provavelmente é loop.
- O limite de 50 ainda existe como safety net para casos onde a repetição varia (ex: loop com argumentos levemente diferentes a cada iteração).
- Mensagem de abort informativa enviada ao usuário antes de encerrar o loop.
