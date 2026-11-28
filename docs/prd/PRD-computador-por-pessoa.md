[PRD]
# PRD Computador por pessoa: um computador de cada um, e nada sai dele sem a pessoa aprovar

> **Situação em 27/11/2026:** o mantenedor decidiu que vale (C2 a C7, em
> 27/11), no desenho do Supernova. Os detalhes de cada decisão (tamanhos,
> limites, isolamento) são fechados na linha de base (E25.0) e nas etapas de
> E26 a E29, que ainda serão escritas a partir dele.
>
> **Depende de:** [PRD Rede e interoperabilidade](PRD-rede-e-interop.md)
> (a conexão conferida) e [PRD Aprovação acessível](PRD-aprovacao-acessivel.md)
> (o pedido que a pessoa responde de qualquer jeito, e A5).

> **Executor:** agente autônomo, depois das decisões. Leia este documento
> inteiro antes de começar. Execute as etapas **na ordem**, com os quality
> gates verdes e um commit por etapa. **Não improvise decisões.**

## 1. Visão

Hoje o Donkey executa comandos num container descartável e navega num
navegador que roda dentro do próprio daemon. Funciona para "rode este
script", não para "entre no portal do fornecedor e baixe a nota fiscal de
outubro": isso pede um navegador com sessão, arquivos que ficam, e um jeito
de agir no mundo sem que a agente possa agir sozinha.

O Supernova (PRD-K, 26/11) fez isso para pessoas cegas e tetraplégicas, para
quem um computador operado pela agente é autonomia: pagar uma conta, marcar
uma consulta. O mesmo desenho serve a uma equipe pequena, com duas
promessas, garantidas pelo **código**:

1. **Cada pessoa tem o seu computador.** Ninguém vê, usa ou apaga o que é de
   outra pessoa; apagar a pessoa apaga tudo.
2. **Nada sai do computador sem a pessoa aprovar.** Enviar um formulário,
   entrar numa conta, apagar um arquivo dela: a agente pede, a pessoa
   responde do jeito que conseguir, e só então acontece.

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **`bash` e `execute_code`** (`app/sandbox.nim`, `infra/sandbox/`): cada
  chamada é um `docker run --rm` (ou `podman`), sem rede por padrão
  (`allow_network = false`), raiz só de leitura, imagem configurável; ou
  Wasm (wasmtime, com `prlimit`). **Nada fica entre chamadas**, e **o
  próprio daemon chama o Docker** (tem acesso ao socket).
- **Navegador** (`adapters/tools/browser.nim`): Lightpanda por CDP, um
  subprocesso **do daemon**, com checagem de SSRF antes de navegar e a
  janela de *DNS rebinding* documentada. Navega, lê e tira foto da tela;
  não preenche formulário com segredo nem guarda sessão por pessoa.
- **Arquivos da pessoa:** o paddock (`{paddocks}/{uuid}/`), lido e escrito
  pelas ferramentas `fs_*` sob aprovação.
- **Segredos por pessoa:** existe um port (`PersonSecretsPort`) usado pelo
  token do GitHub (E11); o cofre do operador é AES-256-GCM.
- **Aprovação:** botões e `/approve`, o turno espera até 300 s (ver PRD
  Aprovação).
- **No Supernova (PRD-K):** um container por pessoa com gVisor (1,5 GB, até 4
  ligados, desliga após 15 min parado); um **despachante** separado tem o
  socket do Docker e o processo principal nunca tem; o portão intercepta no
  navegador o que muda estado e, no shell, a saída só alcança repositórios
  de pacote; cofre de senhas que preenche o campo sem o modelo ver; captcha
  pede ajuda humana por um link da tela (túnel, 15 min, uma sessão); o
  `evaluate` (JavaScript arbitrário) saiu; o navegador que rodava no
  processo principal foi aposentado (auditoria de 27/11, A1).

## 3. Decisões

| # | Decisão |
|---|---|
| C1 | **[proposta]** **O navegador sai do processo do daemon** (como o A1 do Supernova): o Lightpanda passa a rodar num container próprio, sem os segredos da instância, com a saída pela conexão conferida. Vale mesmo que o resto desta PRD não seja feito. |
| C2 | **Vale (mantenedor, 27/11).** Escopo (por pessoa, como o Supernova, ou por agente ou equipe) fechado na linha de base, medindo a memória da VPS. Um computador persistente por pessoa custa memória (o Supernova reserva 1,5 GB e liga até 4) e operação. Para equipes pequenas numa VPS, talvez **por agente nomeado** ou **por equipe**, não por pessoa. |
| C3 | **Vale, no desenho do Supernova (mantenedor, 27/11); detalhe na linha de base:** isolamento.** gVisor (como o Supernova), Docker comum com `seccomp` e sem capacidades, ou microVM (Firecracker). |
| C4 | **Vale, no desenho do Supernova (mantenedor, 27/11); detalhe na linha de base:** o despachante.** Tirar o socket do Docker do daemon (como o Supernova) é a mudança de segurança maior; hoje o `bash` precisa dele. |
| C5 | **Vale, no desenho do Supernova (mantenedor, 27/11); detalhe na linha de base:** o portão.** No navegador, interceptar pedidos que mudam estado (o desenho do Supernova); no shell, saída só para repositórios de pacote, lista que cresce com aprovação. |
| C6 | **Vale, no desenho do Supernova (mantenedor, 27/11); detalhe na linha de base:** cofre de senhas.** A pessoa passa a senha por comando; o código preenche o campo direto; nunca vai ao modelo nem ao histórico. Onde guardar (o `PersonSecretsPort` existente?) e se a voz pode ditar (o Supernova recusa: a transcrição passa por provider externo). |
| C7 | **Vale, no desenho do Supernova (mantenedor, 27/11); detalhe na linha de base:** a tela.** Captcha e 2FA pedem uma pessoa: um link da tela (noVNC) por túnel, ou nada disso no Donkey. |

## 4. Fora de escopo

- Pagamentos.
- Agir sem pedido (proatividade não usa o computador: PRD Proatividade, P-I3).
- Computador para quem não é membro da instância.

## 5. Quality gates

Os de sempre (`CLAUDE.md`). Mais, como no Supernova:

- **Docker falso** nos testes do despachante.
- **Testes de rede do computador** na imagem: o shell não sai da lista; o
  navegador não envia sem autorização; um computador não alcança outro nem
  o daemon.
- **Leitor de tela** em todo pedido (PRD Aprovação).

## 6. Invariantes (as do Supernova, para valerem quando as decisões saírem)

- **C-I1 – Nada sai sem autorização.**
- **C-I2 – Só a pessoa decide** (PRD Aprovação, A-I1).
- **C-I3 – A senha não chega ao modelo:** nenhum prompt, transcrição ou log.
- **C-I4 – Computadores não se veem.**
- **C-I5 – O daemon não tem o socket** (se C4 for sim).
- **C-I6 – Efeito externo se conta pelo registro:** o que a pessoa ouve
  sobre um envio vem do registro do portão, não do relato do modelo.
- **C-I7 – Nada sobra:** apagar a pessoa apaga volume, sessão, cofre e
  autorizações.

## 7. Épicos e etapas

### E25 — O navegador fora do daemon (C1)

#### E25.0: Linha de base

O que o navegador faz hoje, quanto ocupa, quem o usa (ferramentas, sondas
de agentes nomeados).

**Aceite:**
- [ ] `docs/relatorios/PRD-computador-base.md`.
- [ ] Commit: `docs: PRD computador, linha de base`.

#### E25.1: O navegador num container

Lightpanda num container próprio, sem variáveis da instância, CDP por uma
porta local; o daemon fala com ele como hoje.

**Aceite:**
- [ ] Um teste confere que o ambiente do container do navegador não tem
      nenhuma variável do vault.
- [ ] Commit: `feat(navegador): fora do processo do daemon`.

#### E25.2: A saída do navegador conferida

A rede do container do navegador sai por um proxy que conecta ao endereço
conferido (PRD Rede, R1); fecha a janela de rebinding do navegador.

**Aceite:**
- [ ] Teste de rebinding no navegador.
- [ ] Commit: `fix(navegador): a saída vai ao endereço conferido`.

### E26 — O despachante (se C4)

Etapas a escrever depois de C3 e C4: o serviço que liga, desliga e apaga
containers com parâmetros fixos; o daemon sem o socket; o `bash` passando
por ele.

### E27 — O computador de cada um (se C2)

Etapas a escrever depois de C2 e C3: um container persistente (por pessoa,
agente ou equipe), volume próprio, liga quando usa e desliga parado, limite
de ligados, apagado com a pessoa.

### E28 — O portão (se C5)

Etapas a escrever depois de C5: interceptação no navegador, proxy de saída
no shell, autorizações (uso único, da tarefa, por prazo) pelo caminho da
PRD Aprovação.

### E29 — Cofre de senhas e a tela (se C6 e C7)

Etapas a escrever depois de C6 e C7: `/senha`, preenchimento sem o modelo,
sessões guardadas; o link da tela para captcha e 2FA.

## 8. Riscos

- **Memória numa VPS.** Um navegador com sessão ocupa centenas de MB; o
  limite de ligados e o desligamento por inatividade são obrigatórios, não
  ajustes.
- **O socket do Docker.** Enquanto o daemon o tiver (hoje), um comando
  escapado do sandbox que chegue ao daemon controla o host; é o motivo do
  despachante (C4).
- **A agente enganada por uma página.** O portão garante ações, não sigilo:
  uma página hostil pode convencer a agente a pedir algo; o pedido mostra o
  destino real (A-I2), e a pessoa decide.
