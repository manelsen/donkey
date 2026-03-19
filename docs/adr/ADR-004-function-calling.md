# ADR-004 — Function calling via tools array estruturado

**Status:** Aceito
**Data:** 2026-03 (F2 revisão)

## Contexto

O agente precisa chamar ferramentas (MCP tools, native tools) de forma estruturada. A abordagem inicial injetava as tools como texto no system prompt e esperava que o modelo gerasse JSON em formato correto. O modelo ignorava a estrutura e produzia chamadas inconsistentes.

## Decisão

Usar o formato nativo de function calling de cada provider, não texto no system prompt.

### OpenAI-compatible (OpenRouter, Zhipu)

**Request:**
```json
{
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "bash",
        "description": "Execute a bash command",
        "parameters": { "type": "object", "properties": { "cmd": { "type": "string" } } }
      }
    }
  ],
  "tool_choice": "auto"
}
```

**Response:**
```json
{
  "choices": [{
    "message": {
      "role": "assistant",
      "content": null,
      "tool_calls": [
        { "id": "call_abc", "type": "function", "function": { "name": "bash", "arguments": "{\"cmd\":\"ls\"}" } }
      ]
    }
  }]
}
```

**Histórico — turn do assistant com tool_calls deve ser registrado antes dos resultados:**
```nim
history.addAssistantWithToolCalls(resp.text, resp.toolCalls)
# ...execute tools...
history.addToolResult(call.id, result)
```

### Providers com formato diferente (a implementar)

- **Anthropic**: `tool_use`/`tool_result` content blocks — implementação pendente (ADR futuro)
- **Gemini**: `functionCall`/`functionResponse`; `requiresUserFirst` — implementação pendente

## Racional

- Models respondem com chamadas estruturadas e confiáveis ao invés de texto livre.
- IDs de tool call (`call_abc`) permitem correlacionar resultado com chamada específica no histórico.
- Providers que não suportam function calling nativo continuam recebendo tools no system prompt como fallback (caps `toolCalling: false`).

## Consequências

- `ChatMessage` precisa de `toolCalls: seq[ToolCallRequest]` e `toolCallId: string` — campos adicionados.
- `addAssistantWithToolCalls` é obrigatório antes de adicionar tool results — ordem importa para a API.
- Providers sem function calling nativo (ex: modelos antigos) continuam usando text-in-system-prompt — é a mesma path de código, apenas `req.tools` fica vazio.
