## github_token — each person's own GitHub token (E11.2).
##
## Writing to GitHub (E11) goes out with the token of the person who asked,
## so GitHub records who acted and each one writes only where they already
## can. `/github token <TOKEN>` keeps it in the person's encrypted vault; it
## is accepted only in a private conversation (elsewhere it has already been
## seen: the person is told to revoke it). The command is local: it never
## reaches the session, so the token is not in the conversation's history.
## Reading keeps using the instance's token.

import std/strutils
import ../core/pipeops
import ../core/types

const GithubTokenSecret* = "GITHUB_TOKEN"

type PersonSecretsPort* = object
  get*:    proc(userId: UserId; name: string): Result[string, string] {.gcsafe, raises: [].}
    ## "" when there is none.
  set*:    proc(userId: UserId; name, value: string): Result[void, string] {.gcsafe, raises: [].}
  remove*: proc(userId: UserId; name: string): Result[void, string] {.gcsafe, raises: [].}

var gPersonSecrets {.threadvar.}: PersonSecretsPort
  ## Configured at startup on the daemon loop's thread, where turns run.

proc configurePersonSecrets*(port: PersonSecretsPort) =
  gPersonSecrets = port

proc currentPersonSecrets*(): PersonSecretsPort {.gcsafe.} =
  gPersonSecrets

const HowTo = "Crie um token em https://github.com/settings/personal-access-tokens " &
  "(fine-grained), com acesso aos repositórios em que o Donkey vai escrever e a " &
  "permissão Issues: read and write (Pull requests: read and write, para comentar " &
  "em PRs). Depois mande, em mensagem direta: `/github token <TOKEN>`."

func looksLikeGithubToken*(token: string): bool =
  ## The formats GitHub issues: fine-grained (github_pat_), classic (ghp_),
  ## OAuth (gho_), app user-to-server (ghu_).
  (token.startsWith("github_pat_") or token.startsWith("ghp_") or
   token.startsWith("gho_") or token.startsWith("ghu_")) and
    token.len in 30 .. 255 and token.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9', '_'})

proc githubCommand*(secrets: PersonSecretsPort; userId: UserId; value: string;
                    privateChat: bool): Result[string, string] =
  ## `/github`, `/github token <TOKEN>`, `/github esquecer`.
  let words = value.strip.splitWhitespace
  if words.len == 0:
    let kept = ? secrets.get(userId, GithubTokenSecret)
    if kept.len > 0:
      return ok("Seu token do GitHub está configurado: o que o Donkey escrever no " &
                "GitHub por você sai com ele. Para apagá-lo: `/github esquecer`.")
    return ok("Você ainda não guardou um token do GitHub; sem ele, o Donkey só lê. " & HowTo)
  case words[0].toLowerAscii
  of "token":
    if not privateChat:
      return err("Por segurança, só aceito o token em mensagem direta comigo. Como ele " &
                 "apareceu nesta conversa, revogue-o no GitHub e crie outro.")
    if words.len < 2 or not looksLikeGithubToken(words[1]):
      return err("Isso não parece um token do GitHub. " & HowTo)
    ? secrets.set(userId, GithubTokenSecret, words[1])
    ok("Token guardado, cifrado, só para você. Apague daqui a mensagem em que você o " &
       "mandou: ela continua no histórico do aplicativo.")
  of "esquecer", "forget", "apagar":
    ? secrets.remove(userId, GithubTokenSecret)
    ok("Token do GitHub apagado.")
  else:
    err("Uso: `/github` (estado), `/github token <TOKEN>` (em mensagem direta), " &
        "`/github esquecer`.")
