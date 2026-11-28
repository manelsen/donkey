[PRD]
# PRD WhatsApp via GOWA: o WhatsApp como as pessoas usam, com o risco à vista

> **Situação em 27/11/2026:** aprovada em princípio pelo mantenedor ("GOWA
> vai bem", 27/11): o GOWA entra como **segundo modo** do canal WhatsApp,
> ao lado da Cloud API. As decisões marcadas **[proposta]** ele confirma
> antes da execução.
>
> **Depende de:** nada novo; independe das outras PRDs da quinta rodada e
> pode ser executada a qualquer momento. Destrava a proatividade no WhatsApp
> ([PRD Proatividade](PRD-proatividade.md), P7) e o áudio encaminhado
> ([PRD Mídia acessível](PRD-midia-acessivel.md), M6).

> **Executor:** agente autônomo. Leia este documento inteiro antes de
> começar. Execute as etapas **na ordem**. Cada etapa termina com os quality
> gates verdes e um commit próprio. Se a sessão for interrompida, retome pela
> primeira etapa sem commit. **Não improvise decisões.**

## 1. Visão

O Donkey é para humanos, e humanos estão no WhatsApp com o número deles, com
notas de voz, figurinhas, mensagens encaminhadas e grupos. A Cloud API
oficial serve a empresas: exige conta de negócios, verificação, número
dedicado, e só deixa o Donkey falar primeiro com um *template* aprovado pela
Meta, fora da janela de 24 h.

O **GOWA** (`go-whatsapp-web-multidevice`, MIT, sobre o whatsmeow) é uma
ponte que se conecta como um aparelho vinculado a um número comum. Ele dá ao
Donkey o WhatsApp de uma pessoa, com um preço claro: **não é API oficial**, e
o número pode ser deslogado ou suspenso.

Duas promessas:

1. **Quem escolhe o GOWA sabe o que escolheu.** A documentação, o `doctor` e
   o primeiro log dizem que não é oficial, o que pode acontecer ao número e
   o que o GOWA vê.
2. **A queda nunca é silenciosa.** Se o número cair, o operador e as pessoas
   afetadas sabem por outro canal, com o caminho de volta (o código de
   pareamento) na mesma mensagem.

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **O WhatsApp do Donkey hoje é a Cloud API** (`adapters/channel/whatsapp.nim`,
  `whatsapp_runtime.nim`, `whatsapp_bots.nim`, `domain/channels/whatsapp_pure.nim`,
  cerca de 780 linhas): webhook em `/webhook/whatsapp` com
  `WHATSAPP_VERIFY_TOKEN` e assinatura por `WHATSAPP_APP_SECRET`; envio por
  `graph.facebook.com` com `WHATSAPP_ACCESS_TOKEN` e
  `WHATSAPP_PHONE_NUMBER_ID`; vários números (`[[bots]]` com
  `phone_number_id`); mídia na entrada; `send_file`; a pessoa é o telefone.
- **Pendência aberta:** confirmar se um BSUID (`BR.…`) da Cloud API pode ser
  destinatário (ROADMAP, pendências fora do código, WA-009).
- **O GOWA no Supernova** (PRD-C e `docs/operations/WHATSAPP.md`, conferidos
  contra o GOWA **v9.10.0**):
  - webhook com envelope `event`, `device_id`, `payload`; assinatura HMAC
    SHA-256 em `X-Hub-Signature-256` (`sha256=…`) com segredo compartilhado;
  - eventos usados: `message`, `device.logged_out`, `device.temporary_ban`;
  - envio: `POST /send/message` (`phone`, `message`, `reply_message_id`),
    `/send/image`, `/send/audio` (nota de voz), `/send/file`, com basic auth
    e `X-Device-Id`;
  - pareamento por código (`/app/login-with-code?phone=…`) ou QR (`/app/login`);
  - a pessoa às vezes vem como **LID** (identificador oculto) além do
    telefone: o Supernova aprende o par quando os dois chegam juntos;
  - o GOWA guarda a sessão e a mídia nos volumes dele e **serve a mídia sem
    autenticação** (`/statics/…`): a porta só pode ficar no loopback;
  - variáveis que precisam ficar desligadas: resposta automática, atualização
    automática da interface, o MCP próprio, eventos de mensagens enviadas.
- **Canal como processo** (E12.3) e supervisão (E12.2) existem; um canal de
  webhook não tem thread própria para supervisionar.

## 3. Decisões

| # | Decisão |
|---|---|
| W1 | **Decidida (27/11):** o GOWA é um **segundo modo** do canal WhatsApp; a Cloud API continua. |
| W2 | **[proposta]** O **mesmo canal** (`whatsapp`): a pessoa continua sendo o telefone, a mesma identidade nos dois modos. O modo é escolhido por número: `WHATSAPP_MODE = "cloud"` (padrão) ou `"gowa"` para o número padrão; `mode = "gowa"` num `[[bots]]` de WhatsApp. |
| W3 | **[proposta]** O GOWA roda **fora do daemon**, num container próprio, com a versão **fixada por digest** (começando pela v9.10.0, a que o Supernova conferiu); o Donkey fala com ele por REST com basic auth, e ele com o Donkey pelo webhook assinado. Atualizar o GOWA é trocar o digest e regravar as fixtures. |
| W4 | **[proposta]** A porta do GOWA só no **loopback** do host; o `doctor` recusa uma configuração que a publique em outro endereço. |
| W5 | **[proposta]** **Grupos desligados por padrão** (`WHATSAPP_ALLOW_GROUPS=0`): uma mensagem de grupo é descartada sem leitura, com métrica; ligados, entram pela política de grupo que os outros canais já têm. |
| W6 | **[proposta]** **A queda:** `device.logged_out` ou `device.temporary_ban` marca o canal como `down` no status, avisa o operador no log e **por outro canal** (o primeiro configurado entre Telegram, Discord, Signal), já com um código de pareamento novo quando for logout; `donkey ctl whatsapp pair <telefone>` gera outro. |
| W7 | **[proposta]** **LID:** o par telefone↔LID é aprendido quando os dois chegam juntos e guardado; uma mensagem só com LID desconhecido é respondida pelo LID e a pessoa é tratada como nova até o par aparecer. |
| W8 | **[proposta]** **O que o GOWA dá a mais e o Donkey usa:** nota de voz nativa (`ptt`) para `/voz`; a marca de **encaminhada** (M6 da PRD Mídia); sem janela de 24 h (a proatividade vale no modo GOWA, PRD Proatividade P7). |

## 4. O que muda para quem usa

- O operador escolhe o modo; no GOWA, pareia o número com um código digitado
  no celular, sem navegador.
- As pessoas falam com o Donkey no WhatsApp delas como falam com qualquer
  contato: voz, figurinha, encaminhar.
- Se o número cair, chega uma mensagem no Telegram (ou no canal configurado)
  dizendo o que houve e com o código para parear de novo.

## 5. Fora de escopo

- Trocar a Cloud API pelo GOWA (W1).
- A interface web do GOWA (o pareamento é por código; QR só por túnel SSH,
  documentado).
- Status, chamadas, comunidades, canais do WhatsApp.

## 6. Quality gates

Os de sempre (`CLAUDE.md`). Mais:

- **Um GOWA falso** nos testes, com **payloads gravados do GOWA real** da
  versão fixada (um script em `dev/gowa/`, como as fixtures do PRD Rede), não
  JSON escrito à mão.
- **Nenhum teste fala com o WhatsApp.**

## 7. Invariantes (cada uma com teste)

- **W-I1 – Sem assinatura, nada entra.** Um webhook sem HMAC válido é 401,
  sem detalhes, e não chega a nenhum turno.
- **W-I2 – A queda não é silenciosa.** `device.logged_out` e
  `device.temporary_ban` mudam o status e geram o aviso por outro canal;
  nunca pelo WhatsApp que caiu.
- **W-I3 – A mesma pessoa nos dois modos.** Um telefone que falava pela
  Cloud API e passa a falar pelo GOWA continua o mesmo usuário, com a mesma
  memória.
- **W-I4 – Grupo desligado não lê.** Com W5 no padrão, nenhuma mensagem de
  grupo chega a um turno, nem uma menção.
- **W-I5 – O próprio Donkey não volta.** Uma mensagem enviada pelo Donkey
  (`is_from_me`) nunca vira turno.

## 8. Épicos e etapas

### E30 — O GOWA no lugar

#### E30.0: Linha de base e gravador

Conferir a seção 2 contra o GOWA da versão escolhida (openapi e payloads);
`dev/gowa/`: um GOWA real num container local, pareado com um número de
teste, e um script que grava os webhooks e as respostas da API.

**Aceite:**
- [ ] `docs/relatorios/PRD-whatsapp-gowa-base.md` com a conferência.
- [ ] Fixtures gravadas em `tests/fixtures/gowa/`, com a versão no nome.
- [ ] Commit: `dev(gowa): linha de base e gravador`.

#### E30.1: O modo na configuração

W2: `WHATSAPP_MODE`, `mode` nos `[[bots]]`, as variáveis do GOWA
(`WHATSAPP_GOWA_URL`, `WHATSAPP_GOWA_BASIC_AUTH`, `WHATSAPP_GOWA_WEBHOOK_SECRET`),
validação e o aviso do primeiro log (promessa 1).

**Aceite:**
- [ ] Sem `WHATSAPP_MODE`, nada muda (Cloud API).
- [ ] Commit: `feat(whatsapp): o modo gowa na configuração`.

#### E30.2: Entrada

`domain/channels/gowa_pure` lê o envelope e a mensagem (texto, mídia,
encaminhada, resposta a outra, grupo, `is_from_me`); o receptor de webhooks
ganha a rota do modo GOWA com a assinatura.

**Aceite:**
- [ ] W-I1, W-I4 e W-I5 testados contra as fixtures gravadas.
- [ ] Commit: `feat(whatsapp): entrada pelo GOWA`.

#### E30.3: Saída

Texto (com divisão), resposta citando a mensagem, imagem, arquivo do
paddock (`send_file`), nota de voz (`ptt`), com basic auth; contra o GOWA
falso.

**Aceite:**
- [ ] Cada tipo de envio testado.
- [ ] Commit: `feat(whatsapp): saída pelo GOWA`.

#### E30.4: Mídia na entrada

Baixar a mídia do GOWA com autenticação, pelo mesmo caminho dos anexos (E9),
com o limite de tamanho do canal.

**Aceite:**
- [ ] Commit: `feat(whatsapp): mídia recebida pelo GOWA`.

### E31 — A pessoa e o número

#### E31.1: Telefone e LID

W7: o par aprendido e guardado; a mensagem só com LID.

**Aceite:**
- [ ] W-I3 testado (Cloud API e GOWA, o mesmo telefone).
- [ ] Commit: `feat(whatsapp): telefone e LID`.

#### E31.2: Pareamento

`donkey ctl whatsapp pair <telefone>` pede o código ao GOWA e o mostra;
`donkey ctl whatsapp status` diz se o número está conectado.

**Aceite:**
- [ ] Contra o GOWA falso.
- [ ] Commit: `feat(ctl): parear o WhatsApp pelo GOWA`.

#### E31.3: A queda

W6: status `down`, aviso ao operador e por outro canal, com o código novo
quando for logout.

**Aceite:**
- [ ] W-I2 testado.
- [ ] Commit: `feat(whatsapp): a queda avisada por outro canal`.

### E32 — Operação

#### E32.1: O compose e o `doctor`

Um `docker-compose` de exemplo com o GOWA fixado por digest, as variáveis
que ficam desligadas (seção 2), a porta no loopback; o `doctor` confere W4.

**Aceite:**
- [ ] Commit: `ops(whatsapp): o GOWA no compose, conferido pelo doctor`.

#### E32.2: Documentação

`docs/topics/channels.md` (os dois modos, como escolher, o que o GOWA vê e
guarda, o risco ao número, parear, a queda) e `docs/topics/secrets.md`.

**Aceite:**
- [ ] Commit: `docs: WhatsApp pelo GOWA`.

## 9. Riscos

- **O número.** Deslogado ou suspenso a qualquer momento, por decisão do
  WhatsApp. Mitigação: o aviso (W6), os tetos da proatividade e a
  recomendação, na documentação, de um número dedicado.
- **O GOWA quebra com o WhatsApp.** O protocolo muda; a ponte para até ser
  corrigida. Mitigação: versão fixada, atualização à mão com as fixtures
  regravadas, o status mostrando a queda.
- **Um terceiro no meio.** O GOWA vê as mensagens e guarda a mídia. Mitigação:
  container próprio, loopback, volumes no disco da instância, e a
  documentação dizendo isso com todas as letras.
