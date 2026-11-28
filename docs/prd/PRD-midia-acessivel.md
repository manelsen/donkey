[PRD]
# PRD Mídia acessível: nada que a pessoa manda some, e a resposta vem do jeito que ela precisa

> **Situação em 27/11/2026:** rascunho. As decisões marcadas **[proposta]**
> são padrões sugeridos que o mantenedor confirma antes da execução; **M3**
> (quem lê áudio, vídeo e documento) está em aberto.
>
> **Depende de:** mídia nos canais (E9) e as ferramentas de áudio
> (`transcribe_audio`, `text_to_speech`), no master.
> **Vem antes de:** [PRD Aprovação acessível](PRD-aprovacao-acessivel.md),
> E20.3 (a voz decide).

> **Executor:** agente autônomo. Leia este documento inteiro antes de
> começar. Execute as etapas **na ordem**. Cada etapa termina com os quality
> gates verdes e um commit próprio. Se a sessão for interrompida, retome pela
> primeira etapa sem commit. **Não improvise decisões.**

## 1. Visão

Uma nota de voz, um PDF de boleto, uma foto de um documento, um vídeo curto:
é assim que muita gente fala com um assistente pelo celular. Para quem é
cego, tem pouca mobilidade ou só consegue ditar, é o único jeito.

Duas promessas, garantidas pelo código:

1. **Nada some em silêncio.** Todo tipo que chega por um canal vira texto
   para a agente, ou uma nota com o motivo ("[um vídeo de 12 minutos, que
   não consigo ver]"). A agente sempre responde sobre o que chegou.
2. **A pessoa escolhe como ouve a resposta.** Em voz, curta, longa, com
   descrição detalhada de imagens, com a transcrição devolvida; e isso fica
   guardado como preferência dela.

## 2. Contexto (conferido em 27/11/2026 no master `81f0c854`)

- **Imagens** (`docs/topics/media.md`): baixadas para o paddock; até 4 vão
  inline ao modelo que vê; acima disso, ou para um modelo só de texto, viram
  um marcador que aponta para `inspect_image`. Formatos não suportados (SVG,
  HEIC, BMP, TIFF) viram marcador para `fs_read`.
- **Outros arquivos** viram um marcador com o caminho; o modelo decide se lê
  (`fs_read`, `text_read`). **Uma nota de voz é um desses:** só vira texto
  se o modelo chamar `transcribe_audio`, e não fica transcrita na memória.
- **Áudio** (`app/tools/audio_tools.nim`): STT e TTS por um endpoint
  compatível com OpenAI (`DONKEY_STT_*`, `DONKEY_TTS_*`, padrão
  `whisper-1` e `tts-1` com `OPENAI_API_KEY`). `text_to_speech(as_voice =
  true)` manda nota de voz onde o canal tem `cfSendVoice`.
- **Anexos entram** em quase todos os canais (E9); alguns canais trocam o
  que não sabem ler por uma nota curta (BlueBubbles, SimpleX), outros não
  dizem nada: **a conferir por canal na linha de base**.
- **Preferências por pessoa** existem (`PREFERENCES.md`, idioma, provider,
  estilo), mas nenhuma sobre mídia nem sobre como responder.
- **No Supernova (PRD-A, 24 e 25/11):** tudo que chega é lido antes do
  turno (voz em transcrição literal, vídeo em audiodescrição com as falas,
  documento pelo essencial primeiro, figurinha animada quadro a quadro,
  localização, contato e enquete em texto) e fica na memória; nada some;
  `/voz`, `/transcricao`, `/curto`, `/longo`, `/cego`; fixtures gravadas
  contra a API real (`dev/gemini/gravar.py`).

## 3. Decisões

| # | Decisão |
|---|---|
| M1 | **[proposta]** **Nada some:** todo tipo que um canal entrega (voz, áudio, vídeo, documento, imagem, figurinha, localização, contato, enquete, o que mais vier) vira texto ou nota antes do turno. A nota diz o tipo, o tamanho ou a duração e por que não foi lido. |
| M2 | **[proposta]** **Voz e áudio são transcritos antes do turno**, pelo STT configurado; a transcrição entra no texto do turno como se a pessoa tivesse escrito e **fica na memória**. O áudio continua no paddock. |
| M3 | **Em aberto: quem lê o resto.** (a) **Só o que já existe**: PDF e texto pelo extrator local; vídeo vira nota. (b) **Um leitor multimodal** (Gemini, como no Supernova) para vídeo, documento escaneado e imagem quando o modelo da agente não vê, com custo contado. **Recomendação: começar por (a)** e abrir (b) como etapa separada, porque ela traz um provider e um custo novos. |
| M4 | **[proposta]** Documento: o **essencial primeiro** (num boleto, valor, vencimento e a linha digitável completa; num contrato, partes e prazos), depois o texto. O essencial é pedido ao modelo da agente num prompt fixo, não inventado pelo código. |
| M5 | **[proposta]** Preferências por pessoa, guardadas no `PREFERENCES.md` e apagadas com o resto: `/voz` (respostas em nota de voz onde o canal manda voz), `/transcricao` (devolve a transcrição dos áudios da própria pessoa), `/curto` e `/longo` (tamanho das respostas), `/cego` (descrição detalhada de imagens e respostas sem depender de ver nada). Cada um liga e desliga (`/voz não`). |
| M6 | **[proposta]** Áudio **encaminhado** volta como transcrição, sem passar pelo modelo, nos canais que dizem que a mensagem foi encaminhada. |
| M7 | **[proposta]** Custo e limites: a transcrição de um áudio passa do limite configurado (padrão **20 min**) vira nota; o custo aparece no `/insights` como o de um turno. |

## 4. O que a pessoa vive

- Manda uma nota de voz: a agente responde ao que foi dito; uma semana
  depois, "o que eu te disse sobre o fornecedor?" acha a nota, porque o texto
  dela está na memória.
- Manda o PDF de um boleto: "Boleto da Enel, R$ 312,40, vence em 5/12.
  Linha digitável: …"; depois, o resto, se ela pedir.
- Manda um vídeo e o Donkey não lê vídeo: "Recebi um vídeo de 3 minutos,
  mas ainda não consigo assistir. Quer me contar do que se trata?"
- `/voz`: as respostas chegam como nota de voz; `/voz não` volta ao texto.
- Encaminha um áudio longo de um colega: recebe a transcrição de volta.

## 5. Fora de escopo

- Responder com vídeo ou imagem gerada.
- Voz em canais que não mandam voz (fica em texto, com aviso uma vez).
- Leitura de vídeo (salvo se M3 for (b)).

## 6. Quality gates

Os de sempre (`CLAUDE.md`). Mais:

- **Nenhum teste chama provider de verdade:** STT, TTS e o leitor são
  testados contra servidores falsos, com **respostas gravadas da API real**
  (um script em `dev/`, como no Supernova), não JSON escrito à mão.
- **Áudio de verdade nas fixtures:** uma nota de voz curta em Opus e uma em
  MP3, como as de `t_voice_reply`.

## 7. Invariantes (cada uma com teste)

- **M-I1 – Nada some.** Para cada tipo que cada canal entrega, o turno
  recebe texto ou nota. O teste percorre os tipos por canal.
- **M-I2 – O que foi ouvido fica.** A transcrição de uma nota de voz está na
  transcrição da sessão e no que a memória guarda daquele turno.
- **M-I3 – A preferência é da pessoa.** `/voz` de uma pessoa não muda a
  resposta de outra, nem num grupo.
- **M-I4 – Falha é nota, não silêncio.** STT fora, limite passado, formato
  desconhecido: a agente recebe a nota com o motivo e responde.

## 8. Épicos e etapas

### E17 — Nada some

#### E17.0: Linha de base

Para cada canal, cada tipo que ele entrega e o que acontece hoje (inline,
marcador, nota, nada).

**Aceite:**
- [ ] `docs/relatorios/PRD-midia-base.md` com a tabela canal × tipo.
- [ ] Commit: `docs: PRD mídia, linha de base`.

#### E17.1: O tipo e a nota

`domain/media/inbound_pure`: o que chegou (tipo, nome, tamanho, duração,
páginas) e a nota padrão para cada caso de M1.

**Aceite:**
- [ ] Testes de cada nota (texto curto, sem emoji no início).
- [ ] Commit: `feat(midia): toda mídia recebida tem tipo e nota`.

#### E17.2: Telegram

Voz, áudio, vídeo, nota de vídeo, documento, figurinha, localização,
contato e enquete passam pelo E17.1.

**Aceite:**
- [ ] M-I1 no Telegram.
- [ ] Commit: `feat(telegram): nada que chega some`.

#### E17.3: WhatsApp

O mesmo, no WhatsApp (Cloud API).

**Aceite:**
- [ ] M-I1 no WhatsApp.
- [ ] Commit: `feat(whatsapp): nada que chega some`.

#### E17.4: Discord, Slack, Mattermost, Teams e Google Chat

**Aceite:**
- [ ] M-I1 nesses canais.
- [ ] Commit: `feat(canais): nada que chega some nos canais de equipe`.

#### E17.5: Os demais canais

Signal, Matrix, SMS, Email, LINE, Feishu, DingTalk, WeCom, WeChat, QQ,
SimpleX, BlueBubbles, ntfy, IRC (só links).

**Aceite:**
- [ ] M-I1 em todos os canais (o teste da linha de base vira o teste final).
- [ ] Commit: `feat(canais): nada que chega some em nenhum canal`.

### E18 — Ler antes do turno

#### E18.0: O gravador

`dev/stt/`: grava respostas reais do STT configurado para as fixtures de
voz (Opus, MP3, um áudio longo, um vazio).

**Aceite:**
- [ ] Commit: `dev(stt): gravador de transcrições`.

#### E18.1: A voz vira texto

M2: antes do turno, o áudio vai ao STT fora do laço; o texto entra no turno
e na memória; falha vira nota (M-I4); limite (M7).

**Aceite:**
- [ ] M-I2 e M-I4 testados contra as fixtures gravadas.
- [ ] Commit: `feat(midia): a voz vira texto antes do turno`.

#### E18.2: Encaminhado volta transcrito

M6, nos canais que marcam o encaminhamento.

**Aceite:**
- [ ] Commit: `feat(midia): áudio encaminhado volta transcrito`.

#### E18.3: Documento pelo essencial

M4 para PDF e texto: extração local, o essencial pedido ao modelo da agente
num prompt fixo, depois o texto.

**Aceite:**
- [ ] Teste com um boleto e um contrato de exemplo (fixtures sem dado real).
- [ ] Commit: `feat(midia): documento pelo essencial primeiro`.

#### E18.4: O leitor multimodal (se M3 for (b))

Vídeo, documento escaneado e imagem para modelo que não vê, por um leitor
configurável, com custo contado.

**Aceite:**
- [ ] Contra respostas gravadas do leitor.
- [ ] Commit: `feat(midia): leitor multimodal`.

### E19 — Como a pessoa quer a resposta

#### E19.1: As preferências

M5: `/voz`, `/transcricao`, `/curto`, `/longo`, `/cego`, no
`PREFERENCES.md`, lidas a cada turno.

**Aceite:**
- [ ] M-I3 testado num grupo.
- [ ] Commit: `feat(preferencias): como a pessoa quer a resposta`.

#### E19.2: A resposta em voz

Com `/voz`, a resposta final vai como nota de voz pelo caminho de
`text_to_speech(as_voice = true)`; o texto é saneado para fala (sem
marcação, sem emoji, números por extenso quando ajuda).

**Aceite:**
- [ ] Canal sem voz: texto, com aviso uma vez.
- [ ] Commit: `feat(voz): /voz responde falando`.

#### E19.3: `/curto`, `/longo` e `/cego` no prompt

Instruções fixas por preferência; `/cego` pede descrição detalhada de
imagens e respostas que não dependem de ver.

**Aceite:**
- [ ] Commit: `feat(preferencias): tamanho e descrição da resposta`.

#### E19.4: Documentação

`docs/topics/media.md` e `commands.md`: o que é lido, o que vira nota, os
comandos, os custos.

**Aceite:**
- [ ] Commit: `docs: mídia acessível`.

## 9. Riscos

- **Custo.** Transcrever todo áudio custa; o limite (M7) e o `/insights`
  mostram, e a pessoa pode desligar a transcrição automática se o operador
  quiser oferecer isso (não proposto).
- **Privacidade.** O áudio vai a um provider externo de STT; hoje já vai,
  quando o modelo chama `transcribe_audio`. A documentação diz para onde.
- **Uma transcrição errada vira memória.** O áudio continua no paddock e a
  pessoa pode pedir para corrigir; a memória guarda que veio de uma voz.
