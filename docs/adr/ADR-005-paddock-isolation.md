# ADR-005 — Paddock por usuário com path enforcement

**Status:** Aceito
**Data:** 2026-03 (F2 revisão)

## Contexto

O bash tool e as ferramentas de filesystem (`find`, `grep`) precisam de um workdir isolado por usuário. Sem isolamento, tool calls de um usuário podem afetar arquivos de outro.

## Decisão

Cada usuário tem um diretório exclusivo: `~/.donkey/paddocks/{uuid}/`

O diretório é criado na primeira execução se não existir (`createDir`). Paths fornecidos pelas tools são normalizados e validados antes de qualquer execução.

### Path enforcement

```nim
proc resolveInPaddock*(path, paddock: string): string =
  ## Colapsa ".." sem syscall — purely string-based
  ## Ex: resolveInPaddock("../../etc/passwd", "/home/u/paddock")
  ##   → "/home/u/etc/passwd"  (fora do paddock, mas não chega a /etc)
  let full = if path.isAbsolute: path else: paddock / path
  var parts: seq[string]
  for seg in full.split('/'):
    case seg
    of "", ".": discard
    of "..":
      if parts.len > 0: discard parts.pop()
    else: parts.add(seg)
  "/" & parts.join("/")

proc inPaddock*(path, paddock: string): bool =
  path.startsWith(paddock & "/") or path == paddock
```

Paths fora do paddock são rejeitados com mensagem de erro — sem execução. Aplicado em:
- `bash` tool: workdir forçado para paddockDir; comando rejeitado se path explícito fora
- `find` tool: diretório de busca validado via `inPaddock`
- `grep` tool: idem

### Symlinks

`pcLinkToFile` e `pcLinkToDir` são ignorados em `walkDir` (find/grep não seguem symlinks). Impede escape via symlink para fora do paddock.

## Racional

- Isolamento entre usuários sem Docker: cada usuário é dono do próprio diretório.
- `resolveInPaddock` é puramente string-based — sem syscall, sem race condition TOCTOU.
- Simples de testar: unit tests determinísticos, sem filesystem real necessário para os casos de validação.

## Consequências

- `smNone` não impede paths absolutos em comandos shell (ex: `cat /etc/passwd`) — documentado em ADR-003 como limitação conhecida de `smNone`.
- `resolveInPaddock` com path relativo usa paddockDir como base — comportamento esperado.
- Diretório criado automaticamente evita erro em primeira execução, mas significa que o diretório sempre existe após a primeira chamada.
