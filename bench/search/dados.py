"""Histórico sintético da Marta com a agente, com valência e erros humanos.

Porta de supernova/dev/bancada/dados.py (mesmo autor). Mudanças: a semente
também desloca cada fato plantado (±2% da conversa, sem trocar a ordem dos
que se corrigem), e `escrever_donkey` grava no formato do Donkey: um
`sessions/<id>.jsonl` por sessão (uma por dia, no fuso da Marta, UTC−3),
linhas {role, text, ts, seq}, e USER.md / MEMORY.md / PREFERENCES.md.

Gera mensagens em episódios (de 2 a 8 mensagens) ao longo de `dias`, com
humor variando, gírias, abreviações, erros de digitação e mensagens digitadas
sem acento. Planta fatos (alguns corrigidos depois, alguns com erro de
digitação, alguns ditos de um jeito e perguntados de outro) e define
perguntas, inclusive sobre coisas nunca ditas.

Tudo é inventado. Nada vem de conversa real.
"""

import json
import os
import random
import unicodedata

PRINCIPAL = "sim:marta"

# ------------------------------------------------------------------ fatos

# Cada fato: id, tipo, posição (0..1), mensagens [(papel, texto)].
# Cada pergunta: id, fato (ou None), pergunta, esperado (o que a resposta
# certa precisa conter), errado (o que denuncia a versão velha ou errada),
# tipo: "fato" | "corrigido" | "nunca" | "quando".
FATOS = [
    ("cardio", 0.04, [
        ("user", "oi! hoje levei minha mãe no cardiologista, foi tranquilo"),
        ("assistant", "Que bom que foi tranquilo. Como ela saiu de lá?"),
        ("user", "saiu bem. guarda o nome dele pra mim? é o dr. Otávio Lacerda, atende no Hospital Madre Teresa"),
        ("assistant", "Guardado: dr. Otávio Lacerda, no Hospital Madre Teresa."),
    ]),
    ("alergia", 0.05, [
        ("user", "outra coisa importante: a mamae é alergica a dipirona. ja deu reação feia uma vez"),
        ("assistant", "Entendido, alergia a dipirona. Vale ter isso escrito num papel na bolsa dela."),
    ]),
    ("irma", 0.10, [
        ("user", "minha irmã Carla vem passar o fds aqui, faz tempo que a gente não se vê"),
        ("assistant", "Que bom! Faz quanto tempo?"),
        ("user", "uns 8 meses. ela mora em Vitória"),
    ]),
    ("wifi", 0.12, [
        ("user", "trocaram o roteador, a senha do wifi novo é girassol42"),
        ("assistant", "Anotado: senha do wifi novo, girassol42."),
    ]),
    ("presente", 0.22, [
        ("user", "comprei o prezente do Joca!! um kit de aquarela com 36 cores, ele vai amar"),
        ("assistant", "Aquarela é um presente lindo. Ele já pinta?"),
        ("user", "rabisca tudo kkkk"),
    ]),
    ("derma_1", 0.30, [
        ("user", "marquei a dermato pra quinta, 14h"),
        ("assistant", "Quinta às 14h, anotado. Quer que eu te lembre na véspera?"),
        ("user", "quero sim"),
    ]),
    ("briga", 0.36, [
        ("user", "to muito chateada. briguei feio com a Carla no telefone"),
        ("assistant", "Sinto muito. Quer me contar o que aconteceu?"),
        ("user", "ela disse que eu só penso em mim e que larguei a mamãe nas costas dela. doeu demais pq não é verdade"),
        ("assistant", "Isso dói mesmo, ainda mais vindo de irmã e sendo injusto. Você cuida muito da sua mãe."),
        ("user", "obg. vou dar um tempo antes de responder"),
    ]),
    ("derma_2", 0.38, [
        ("user", "errei, a dermato é terça e não quinta! ainda bem que olhei o papel"),
        ("assistant", "Corrigido: dermatologista na terça, às 14h."),
    ]),
    ("cirurgia", 0.45, [
        ("user", "a mamae vai ser operada do quadril dia 12, to com medo"),
        ("assistant", "É normal ter medo. Quem vai operar? Já explicaram como vai ser a recuperação?"),
        ("user", "o ortopedista disse que são uns 3 meses de recuperação com fisioterapia"),
    ]),
    ("protocolo", 0.52, [
        ("user", "liguei na operadora pra reclamar da internet. protocolo 20261187736, anota ai"),
        ("assistant", "Anotado: protocolo 20261187736, reclamação da internet."),
    ]),
    ("fisio", 0.60, [
        ("user", "as sessões de fisio da mamãe vão ser com a Marília, segunda e quarta"),
        ("assistant", "Com a Marília, segundas e quartas. Ela vai em casa ou é na clínica?"),
        ("user", "na clinica"),
    ]),
    ("concurso", 0.68, [
        ("user", "PASSEI NO CONCURSO!!!!! nem acredito, 3 anos estudando"),
        ("assistant", "Que notícia! Parabéns, de verdade. Três anos de esforço — como você tá se sentindo?"),
        ("user", "chorando de alegria kkkkk"),
    ]),
    ("sogro", 0.78, [
        ("user", "o Tião, meu sogro, decidiu se mudar pra Ilhéus. o Beto ficou meio abalado"),
        ("assistant", "Mudança grande. O Beto é próximo do pai?"),
        ("user", "muito"),
    ]),
    ("wifi_tarde", 0.93, [
        ("user", "sabe que eu esqueci a senha do banco de novo? tive que resetar"),
        ("assistant", "Acontece. Quer guardar uma dica pra lembrar, sem a senha em si?"),
    ]),
]

PERGUNTAS = [
    ("q_cardio", "cardio", "qual o nome do cardiologista da minha mãe mesmo?",
     ["Lacerda"], [], "fato"),
    ("q_alergia", "alergia", "minha mãe é alérgica a qual remédio?",
     ["dipirona"], [], "fato"),
    ("q_wifi", "wifi", "qual é a senha do wifi?",
     ["girassol42"], [], "fato"),
    ("q_presente", "presente", "o que eu comprei de presente pro Joca?",
     ["aquarela"], [], "fato"),
    ("q_derma", "derma_2", "que dia é a consulta da dermatologista?",
     ["terça"], ["quinta"], "corrigido"),
    ("q_briga", "briga", "por que eu fiquei chateada com a minha irmã aquela vez?",
     ["só pens", "larg"], [], "fato"),
    ("q_cirurgia", "cirurgia", "o que eu te contei sobre a cirurgia da minha mãe?",
     ["quadril"], [], "fato"),
    ("q_protocolo", "protocolo", "qual era o protocolo da reclamação da internet?",
     ["20261187736"], [], "fato"),
    ("q_fisio", "fisio", "com quem vão ser as sessões de fisioterapia da minha mãe?",
     ["Marília"], [], "fato"),
    ("q_concurso", "concurso", "lembra daquela notícia boa que eu te dei sobre a prova?",
     ["concurso"], [], "fato"),
    ("q_sogro", "sogro", "o que eu te falei do meu sogro?",
     ["Ilhéus"], [], "fato"),
    ("q_quando", "cardio", "quando foi que eu te contei do cardiologista da minha mãe?",
     ["@data:cardio"], [], "quando"),
    ("q_cachorro", None, "o que eu te contei do meu cachorro?",
     [], [], "nunca"),
    ("q_chefe", None, "qual é o nome do meu chefe?",
     [], [], "nunca"),
    ("q_lisboa", None, "quando eu te contei da viagem pra Lisboa?",
     [], [], "nunca"),
    ("q_carla_filhos", None, "a Carla tem filhos?",
     [], [], "nunca"),
]

# ------------------------------------------------------------------ enchimento

NOMES = ["Beto", "Joca", "Lu", "Rafa", "Dani", "Sueli", "Paulinho", "Neide"]
DIAS = ["segunda", "terça", "quarta", "quinta", "sexta", "sábado", "domingo"]

EPISODIOS = {
    # valência: lista de episódios; cada episódio, lista de (papel, texto)
    "neutro": [
        [("user", "bom dia"), ("assistant", "Bom dia, Marta! Como acordou?"), ("user", "{humor}")],
        [("user", "hoje é dia de mercado. preciso comprar {comida}"), ("assistant", "Quer que eu monte uma lista?"), ("user", "nao precisa, obg")],
        [("user", "meu chefe pediu o relatório de novo pra {dia}"), ("assistant", "De novo? Dá tempo de fazer com calma até {dia}?"), ("user", "dá, mas que preguiça")],
        [("user", "reunião longa hoje, saí moída"), ("assistant", "Reunião longa cansa mais que trabalho de verdade. Conseguiu descansar?")],
        [("user", "o {nome} mandou mensagem no grupo da família"), ("assistant", "Alguma novidade?"), ("user", "nada, foto de almoço kkk")],
        [("user", "to vendo aquela série de novo"), ("assistant", "Qual temporada?"), ("user", "a segunda, a melhor")],
        [("user", "choveu o dia todo aqui"), ("assistant", "Dia de chuva pede café e sofá. Deu pra ficar em casa?")],
        [("user", "levei a mamãe no médico pra renovar receita"), ("assistant", "Foi tudo bem na consulta?"), ("user", "foi, rotina")],
        [("user", "preciso trocar a senha do email, tá pedindo"), ("assistant", "Vale usar uma frase longa. Quer dicas?")],
        [("user", "o cachorro da vizinha latiu a noite toda"), ("assistant", "Ninguém merece. Conseguiu dormir?"), ("user", "mal")],
        [("user", "fiz bolo de fubá pra mamãe"), ("assistant", "Ela gostou?"), ("user", "comeu dois pedaços")],
        [("user", "{dia} tenho consulta de rotina, me lembra"), ("assistant", "Lembro sim. Que horas?"), ("user", "de manhã, depois vejo")],
        [("user", "o Beto chegou tarde de novo"), ("assistant", "Trabalho?"), ("user", "sim, fechamento do mês")],
        [("user", "to pensando em fazer academia"), ("assistant", "Que tipo de exercício você gosta?"), ("user", "sei la, caminhada talvez")],
        [("user", "comprei {comida} na feira, tava baratinho"), ("assistant", "Feira boa é a melhor coisa da semana.")],
    ],
    "bom": [
        [("user", "dia lindo hoje!! fui caminhar no parque"), ("assistant", "Que delícia! Quanto tempo caminhou?"), ("user", "uma hora, me senti otima")],
        [("user", "o {nome} me ligou só pra conversar, adorei"), ("assistant", "Essas ligações sem motivo são as melhores.")],
        [("user", "meu chefe elogiou o relatório!"), ("assistant", "Merecido! Você caprichou nele."), ("user", "caprichei msm")],
        [("user", "a mamae acordou animada hoje"), ("assistant", "Que bom! O que vocês fizeram?"), ("user", "fomos na padaria")],
    ],
    "ruim": [
        [("user", "dia péssimo"), ("assistant", "Sinto muito. Quer contar o que pesou mais?"), ("user", "tudo um pouco. trabalho, mamãe, cansaço"), ("assistant", "Muita coisa junta. Hoje dá pra tirar um pedaço disso das suas costas?"), ("user", "acho que não. vou dormir cedo")],
        [("user", "to com dor de cabeça desde cedo"), ("assistant", "Bebeu água hoje? Às vezes ajuda."), ("user", "pouca")],
        [("user", "o Beto e eu discutimos por besteira"), ("assistant", "Besteira que cansa. Já conversaram depois?"), ("user", "ainda não")],
        [("user", "não to conseguindo dormir direito"), ("assistant", "Faz quantos dias?"), ("user", "uma semana"), ("assistant", "Uma semana pesa. Se continuar, vale falar com um médico.")],
        [("user", "a mamae teve uma noite ruim, quase não dormi"), ("assistant", "Você também precisa de descanso. Alguém pode revezar com você?"), ("user", "ninguém")],
    ],
}

HUMOR = ["bem", "cansada", "com sono kkk", "mais ou menos", "otima!", "com dor nas costas"]
COMIDA = ["pão", "frutas", "arroz e feijão", "café", "queijo", "verduras", "ovos"]

# ------------------------------------------------------------------ erros humanos


def sem_acento(texto):
    nfd = unicodedata.normalize("NFD", texto)
    return "".join(c for c in nfd if not unicodedata.combining(c))


def erro_digitacao(texto, rng):
    palavras = texto.split(" ")
    candidatas = [i for i, p in enumerate(palavras) if len(p) >= 5 and p.isalpha()]
    if not candidatas:
        return texto
    i = rng.choice(candidatas)
    p = palavras[i]
    j = rng.randrange(1, len(p) - 1)
    tipo = rng.random()
    if tipo < 0.4:
        p = p[:j] + p[j + 1:]                      # letra comida
    elif tipo < 0.8:
        p = p[:j] + p[j + 1] + p[j] + p[j + 2:]    # letras trocadas
    else:
        p = p[:j] + p[j] + p[j:]                   # letra dobrada
    palavras[i] = p
    return " ".join(palavras)


def humanizar(papel, texto, rng):
    if papel != "user":
        return texto
    if rng.random() < 0.35:
        texto = sem_acento(texto)
    if rng.random() < 0.10:
        texto = erro_digitacao(texto, rng)
    if rng.random() < 0.15:
        texto = texto.lower()
    return texto


def preencher(texto, rng):
    return (texto.replace("{nome}", rng.choice(NOMES))
            .replace("{dia}", rng.choice(DIAS))
            .replace("{humor}", rng.choice(HUMOR))
            .replace("{comida}", rng.choice(COMIDA)))


# ------------------------------------------------------------------ geração


def gerar(mensagens_alvo, semente=7):
    """Lista de mensagens [{role, content, at, fato?}], mais antiga primeiro."""
    rng = random.Random(semente)
    corpo = []
    while len(corpo) < mensagens_alvo:
        valencia = rng.choices(["neutro", "bom", "ruim"], [0.65, 0.15, 0.20])[0]
        ep = rng.choice(EPISODIOS[valencia])
        for papel, texto in ep:
            corpo.append({"role": papel,
                          "content": humanizar(papel, preencher(texto, rng), rng)})
    # planta os fatos, do fim para o começo para as posições não andarem;
    # a semente desloca cada um um pouco (derma_1 0,30 e derma_2 0,38 não se
    # cruzam com ±0,02)
    desloc = {fid: rng.uniform(-0.02, 0.02) for fid, _, _ in FATOS}
    for fid, pos, msgs in sorted(FATOS, key=lambda f: -(f[1] + desloc[f[0]])):
        i = int(min(max(pos + desloc[fid], 0.0), 0.99) * len(corpo))
        # começa num limite de episódio: logo depois de uma resposta
        while i < len(corpo) and corpo[i]["role"] != "user":
            i += 1
        corpo[i:i] = [{"role": p, "content": t, "fato": fid} for p, t in msgs]
    # horários: espalhados por ~4 meses, terminando ontem, em rajadas
    fim = 1795392000000  # 2026-11-22 00:00 UTC
    passo = int(120 * 86400000 / len(corpo))
    at = fim - passo * len(corpo)
    for m in corpo:
        at += rng.randint(passo // 4, passo * 7 // 4)
        m["at"] = at
    return corpo


def escrever(dirdados, corpo):
    """Grava no formato da Supernova (um JSONL por conversa) e a transcrição."""
    conv = os.path.join(dirdados, "agents", "sim_marta", "conversations")
    os.makedirs(conv, exist_ok=True)
    with open(os.path.join(conv, "sim_dm-marta_marta.jsonl"), "w") as f:
        for m in corpo:
            f.write(json.dumps({"role": m["role"], "content": m["content"],
                                "at": m["at"]}, ensure_ascii=False) + "\n")
    return conv


def data_do_fato(corpo, fid):
    for m in corpo:
        if m.get("fato") == fid:
            return m["at"]
    return None


# ------------------------------------------------------------------ Donkey

FUSO_MS = -3 * 3600 * 1000

USER_MD = """# USER.md — About Your Human

- **Name:** Marta
- **What to call them:** Marta
- **Timezone:** UTC-03:00
- **Language:** pt-BR
- **Notes:** cuida da mãe quase sozinha.
"""

MEMORY_MD = """# MEMORY.md

- A Marta cuida da mãe quase sozinha e às vezes se cobra demais por isso.
- Ela escreve rápido, sem acento, e ri com kkk. Não é descuido; é o jeito dela.
"""


def sessoes(corpo):
    """Uma sessão por dia local: o histórico fica espalhado em muitos arquivos."""
    dia = lambda at: (at + FUSO_MS) // 86400000
    grupos, atual = [], []
    for m in corpo:
        if atual and dia(m["at"]) != dia(atual[-1]["at"]):
            grupos.append(atual)
            atual = []
        atual.append(m)
    if atual:
        grupos.append(atual)
    return grupos


def escrever_donkey(paddock, corpo):
    """O paddock de um usuário do Donkey com a conversa inteira em sessões."""
    sess_dir = os.path.join(paddock, "sessions")
    os.makedirs(sess_dir, exist_ok=True)
    for nome in os.listdir(sess_dir):
        os.remove(os.path.join(sess_dir, nome))
    for g in sessoes(corpo):
        sid = f"{g[0]['at']}-1"
        caminho = os.path.join(sess_dir, sid + ".jsonl")
        with open(caminho, "w") as f:
            for k, m in enumerate(g, 1):
                f.write(json.dumps({"role": m["role"], "text": m["content"],
                                    "ts": m["at"], "seq": k}, ensure_ascii=False) + "\n")
        os.utime(caminho, (g[-1]["at"] / 1000, g[-1]["at"] / 1000))
    for nome, texto in (("USER.md", USER_MD), ("MEMORY.md", MEMORY_MD),
                        ("PREFERENCES.md", "language: pt-BR\n")):
        with open(os.path.join(paddock, nome), "w") as f:
            f.write(texto)
    return len(sessoes(corpo))
