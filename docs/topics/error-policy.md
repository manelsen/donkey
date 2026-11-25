# Error Policy — Donkey

Politica formal de tratamento de erros por camada.
Define onde erro sobe, onde vira warning, onde silencio e permitido.

---

## 1. Principios

1. **Nenhum erro operacional desaparece sem registro.** Toda falha em caminho critico deve resultar em pelo menos um: retorno explicito, log estruturado, metrica ou evento de observabilidade.
2. **`isOkOr: discard` e `except CatchableError: discard` sao proibidos em caminhos operacionais.**
3. **Logs sao estruturados e seguem formato definido abaixo.**
4. **Silencio so e permitido em cleanup/teardown onde a falha nao tem impacto operacional.**

---

## 2. Formato de log estruturado para erros

Todos os logs de erro devem seguir o padrao:

```
{subsystem}: {acao} failed for {entidade} reason={motivo}
```

Exemplos concretos:

| Camada | Exemplo de log |
|--------|----------------|
| Reminder | `heartbeat.reminder: reminder delivery failed for user=abc123 channel=ckTelegram reason=delivery timeout` |
| Outbound QQ | `qq.outbound: qq send lcaShowAbout failed for user=abc123 reason=network unreachable` |
| Outbound Telegram | `tg.send: network timeout` (ja implementado em outbound_runtime.nim) |

Campos obrigatorios no log:
- **subsystem**: logger name (ex: `heartbeat.reminder`, `qq.outbound`, `tg.send`)
- **acao**: operacao que falhou (ex: `reminder delivery`, `send`, `editMessage`)
- **entidade**: identificador do contexto (ex: `user=abc123`, `channel=ckTelegram`)
- **motivo**: mensagem de erro da excecao ou Result error

Niveis de log por contexto:
- `log.error()`: falhas operacionais que afetam o usuario (envio de mensagem, reminder nao entregue)
- `log.warn()`: falhas recuperaveis ou parcialmente esperadas (retry, fallback ativado)
- `log.info()`: sucesso em operacoes relevantes (mensagem enviada, reminder entregue)

---

## 3. Politica por camada

### 3.1 Outbound (envio de mensagens) — CRITICA

**Regra:** Todo `isOkOr: discard` em envio de mensagens deve ser substituido por log de erro com contexto do usuario.

| Channel | Criticidade | Acao |
|---------|-------------|------|
| QQ | Alta | Log obrigatoria em cada falha de envio |
| Feishu | Alta | Log obrigatoria em cada falha de envio |
| WeCom | Alta | Log obrigatoria em cada falha de envio |
| Telegram | Media | Log ja implementada em outbound_runtime.nim |

Padrao a aplicar:
```nim
qqAdapter.send(msg).isOkOr:
  log.error("qq send lcaShowAbout failed for user=" & $userId & " reason=" & error)
```

### 3.2 Reminders — CRITICA

**Regra:** Falhas em `deliverDueReminders` devem emitir log de erro. O reminder e deletado mesmo em falha de entrega (para evitar loop infinito), mas a falha fica registrada.

Padrao implementado:
```nim
try:
  outboxFn(userId, channel, message)
except CatchableError:
  let errMsg = getCurrentExceptionMsg()
  log.error("reminder delivery failed for user=" & userId &
            " channel=" & channel & " reason=" & errMsg)
```

### 3.3 Webhooks / Channel servers — MEDIA

**Regra:** Erros de conexao em servidores webhook sao comuns e esperados. Log em nivel `warn` e suficiente. Silencio em cleanup (`close`, `wsClose`) e aceitavel.

### 3.4 Memory / Persistence — CRITICA

**Regra:** Falhas em operacoes AGE/cypher e reminders devem emitir log de erro. Sao operacoes que afetam dados persistentes do usuario.

### 3.5 Ferramentas / Native — BAIXA-MEDIA

**Regra:** `file not found` em walk/grep e esperado. Demais erros devem emitir log de warn.

### 3.6 Heartbeat / Contemplation — IMPORTANTE

**Regra:** Falhas em `runAllTasks` e `runCommitmentReview` devem emitir log de erro para permitir diagnostico.

---

## 4. Onde silencio e aceitavel

| Contexto | Justificativa |
|----------|---------------|
| WebSocket close frames | Falha no close e normal em conexoes ja fechadas |
| SSE heartbeat em conexao fechada | Esperado quando cliente desconecta |
| Browser cleanup | Cleanup de recurso externo pode falhar sem impacto |
| Cleanup/teardown geral | Recursos sendo liberados, falha nao tem impacto operacional |

---

## 5. Progresso de aplicacao

### US-005 (esta historia)
- [x] `heartbeat.nim:deliverDueReminders` — `except CatchableError: discard` substituido por log de erro
- [x] `qq_runtime.nim:lcaShowAbout` — `isOkOr: discard` substituido por log de erro
- [x] `qq_runtime.nim:lcaStartIntro` — `isOkOr: discard` substituido por log de erro
- [x] Testes unitarios para politica de erro adicionados em `tests/app/t_error_policy.nim`

### US-006 (concluida)
- [x] 10x `isOkOr: discard` restantes em `qq_runtime.nim` — substituidos por `log.error()`
- [x] 5x `isOkOr: discard` em `feishu_runtime.nim` — substituidos por `log.error()`, logger adicionado ao drain
- [x] 2x `isOkOr: discard` em `wecom_runtime.nim` — helpers `wcReply`/`wcMd` receberam parametro logger
- [x] 2x `isOkOr: discard` em `telegram_runtime.nim` — `handleTelegramCoreCommand` e `handleTelegramTaskCommand` receberam logger
- [x] 2x `isOkOr: discard` em `donkey.nim` sendTyping — `makeTgTypingFn` recebeu logger
- [x] Webhook `except:discard` em `wechat.nim`, `qq.nim`, `wecom.nim`, `http_gateway.nim` — substituidos por `stderr.writeLine` warnings

### Pendente (US-007)
