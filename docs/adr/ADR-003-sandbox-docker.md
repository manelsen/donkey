# ADR-003 — Sandbox para bash tool: Docker bind mount

**Status:** Aceito
**Data:** 2026-03 (F2 revisão)

## Contexto

O bash tool (`executeNativeTool`) executa comandos shell arbitrários em nome do agente. Sem isolamento, o agente tem acesso irrestrito ao disco do host — incluindo paths fora do workspace do usuário.

### Alternativas avaliadas

| Opção | Motivo de rejeição |
|-------|-------------------|
| **WASM (Wasmtime)** | Sem suporte a `fork`/`exec` — comandos shell comuns impossíveis |
| **bwrap (bubblewrap)** | Pacote externo não disponível em todos os ambientes; root ou `SETUID` necessário em alguns kernels |
| **Firejail** | Idem bwrap; mais pesado; não embeddable |
| **Landlock LSM** | Linux 5.13+ only; sem syscall disponível em binários Nim sem wrapper C; não cobre BSD/macOS/Windows |
| **User namespaces** | Linux only; complexidade de implementação; restrições em Ubuntu/Debian por padrão |
| **seccomp** | Restringe syscalls, não filesystem paths — não resolve o problema |
| **Docker named volume** | Volume não é visível no host sem `docker cp` — dificulta inspeção e backup dos arquivos do agente |

## Decisão

Dois modos, selecionáveis em `donkey.toml`:

```toml
[sandbox]
mode  = "docker"          # "none" (default) ou "docker"
image = "alpine"          # imagem Docker; default: alpine
```

**`smNone` (default):** `execCmdEx` com `workingDir = paddockDir`. Sem isolamento real de filesystem — apenas CWD. Documentado como limitação. Adequado para ambientes controlados (VPS privado, single-operator).

**`smDocker`:** Container efêmero com bind mount do paddock:
```
docker run --rm -v {paddock}:/workspace -w /workspace {image} sh -c {cmd}
```
- Host path persiste entre sessões e containers.
- Sem root no container (imagem alpine por padrão).
- Container descartado ao término do comando.
- Zero estado no Docker Engine entre chamadas.

**Paddock por usuário:** `~/.donkey/paddocks/{uuid}/` — isolamento entre usuários por filesystem.

**Path enforcement:** `resolveInPaddock` colapsa `..` sem syscall. `inPaddock` verifica prefix. Paths fora do paddock são rejeitados antes de executar — válido para `smNone` e `smDocker`.

**Startup:** `sandboxLogLevel` emite `warn` se `smNone` (operador ciente), `info` se `smDocker`.

## Consequências

- **smNone:** Caminho absoluto como `/etc/passwd` ainda é acessível — limitação documentada.
- **smDocker:** Requer Docker daemon no host — não adequado para ambientes sem Docker.
- Symlinks em `find`/`grep` são ignorados (`pcLinkToFile`/`pcLinkToDir` → `discard`) em ambos os modos.
- A abstração `sandboxBash(cmd, paddock, mode, image)` permite adicionar modos futuros (ex: `smLandlock`, `smGVisor`) sem alterar o orchestrator ou native_tools.
