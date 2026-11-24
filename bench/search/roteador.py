"""Which router should decide recall's policy for a message?

Recall classifies a message as "about time" by its words ("first", "ago",
"last"…) and then gives recency the largest weight. That mixes questions
about order ("which came first?") with questions about a recent period
("what did we talk about yesterday?"), and the first kind loses its answer
(RESULTS.md, LongMemEval). This compares five routers on the same labelled
messages, with four routes:

  fato      something said before (a fact, a name, the current state of a thing)
  recencia  a recent period ("yesterday", "10 days ago", "last month")
  ordem     when something happened, which came first, time between events
  agora     not about the past (greeting, comment, new request, advice)

Routers: `palavras` (Donkey's word list today: temporal words -> recencia),
`palavras2` (the same words split: recency words -> recencia, order words ->
ordem), Perplexity Decider flash and full through OpenRouter
(/api/alpha/decisions, the `latest` alias), Perplexity Decider 1.3 on
Perplexity's own endpoint (`pplx-direto`), and Gemini Decision 1. The models get the same instructions and option
descriptions.

Measures: routing accuracy against the labels (four routes, and "past or
not" as a gatekeeper would use it), cost and latency; then recall's top 8
with each router's routes (recencia -> the temporal policy, everything else
-> the default), on the cached LongMemEval and Marta graphs.

  python3 -I bench/search/roteador.py --lme-dados DIR --marta-dados DIR
"""
import argparse, concurrent.futures as cf, json, os, re, subprocess, sys, threading, time
import unicodedata

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import bancada  # noqa: E402  (keys)
import dados  # noqa: E402
import longmemeval as lm  # noqa: E402

ROTAS = ["fato", "recencia", "ordem", "agora"]
INSTRUCAO = "What kind of message did the person send to their assistant?"
CRITERIOS = {
    "fato": "Asks about something the person told, said or agreed on earlier in the "
            "conversation: a fact, name, number, preference, or the current state of something.",
    "recencia": "Asks what happened or was discussed in a recent period relative to today: "
                "yesterday, last week, N days ago, in the last month.",
    "ordem": "Asks when something happened, which of two events came first, or how much "
             "time passed between events.",
    "agora": "Does not ask about the conversation's past: a greeting, a comment, a new "
             "request, or a request for advice.",
}

## Labels. LongMemEval: the 60 answerable questions of the sample, by id.
## Preference questions ("Any tips?") do not ask about the past: agora.
LME_ROTA = {
    "gpt4_15e38248": "recencia", "3a704032": "recencia", "311778f1": "recencia",
    "gpt4_1e4a8aec": "recencia", "gpt4_5dcc0aab": "recencia", "8077ef71": "recencia",
    "gpt4_7bc6cf22": "recencia", "gpt4_8279ba03": "recencia",
    "gpt4_59149c77": "ordem", "gpt4_0b2f1d21": "ordem", "gpt4_1d4ab0c9": "ordem",
    "gpt4_0a05b494": "ordem",
    "1d4e3b97": "agora", "57f827a0": "agora", "75832dbd": "agora", "06878be2": "agora",
    "0a34ad58": "agora", "195a1a1b": "agora", "afdc33df": "agora", "75f70248": "agora",
    "8a2466db": "agora", "38146c39": "agora",
}  ## every other answerable question: fato
MARTA_ROTA = {"q_quando": "ordem", "q_lisboa": "ordem"}  ## every other one: fato
NEUTRAS_EN = ["good morning!", "I baked a carrot cake today", "I'm so tired",
              "it's really hot today", "can you help me write a birthday message for Beto?",
              "what do you think about me joining a gym?", "I watched a beautiful movie yesterday",
              "lol", "I miss my grandma", "thanks for today"]
NEUTRAS_PT = ["bom dia!", "fiz bolo de cenoura hoje", "to cansada demais", "que calor hoje",
              "me ajuda a escrever um parabéns pro Beto?", "o que você acha de eu fazer academia?",
              "vi um filme lindo ontem", "kkkkk", "to com saudade da minha vó", "obrigada por hoje"]

## Donkey's word list (domain/memory/query_policy_pure.nim), folded.
TEMPORAIS = {"when", "yesterday", "last", "before", "after", "earlier", "first", "then", "ago",
             "today", "quando", "ontem", "anteontem", "hoje", "antes", "depois", "ultimo",
             "ultima", "ultimos", "ultimas", "primeiro", "primeira", "atras", "passado", "passada"}
RADICAIS = ("recent", "chronolog", "cronol", "anterior")
RECENCIA = {"yesterday", "last", "ago", "today", "ontem", "anteontem", "hoje", "ultimo", "ultima",
            "ultimos", "ultimas", "atras", "passado", "passada"}


def dobrar(t):
    return "".join(c for c in unicodedata.normalize("NFD", t.lower()) if not unicodedata.combining(c))


def palavras(msg):
    ws = re.findall(r"[a-z0-9]+", dobrar(msg))
    return "recencia" if any(w in TEMPORAIS or w.startswith(RADICAIS) for w in ws) else "fato"


def palavras2(msg):
    ws = re.findall(r"[a-z0-9]+", dobrar(msg))
    if any(w in RECENCIA or w.startswith("recent") for w in ws):
        return "recencia"
    if any(w in TEMPORAIS or w.startswith(RADICAIS) for w in ws):
        return "ordem"
    return "fato"


def perguntas():
    return {"rota": {"type": "choice", "instructions": INSTRUCAO, "criteria": CRITERIOS}}


def pplx(modelo):
    def f(msg):
        t = time.time()
        r = bancada.post("https://openrouter.ai/api/alpha/decisions",
                         {"model": modelo, "state": msg, "questions": perguntas()},
                         {"Authorization": "Bearer " + os.environ["OPENROUTER_API_KEY"]}, tentativas=6)
        a = r["answers"]["rota"]
        return a["choice"], a.get("probabilities", {}), time.time() - t, r.get("usage", {}).get("cost", 0)
    return f


def pplx_direto(msg):
    ## Perplexity's own endpoint, model pinned (1.3): the paid access whose
    ## data Perplexity does not train on.
    t = time.time()
    r = bancada.post("https://api.perplexity.ai/v1/decisions",
                     {"model": "pplx-decider-v1.3", "state": msg, "questions": perguntas()},
                     {"Authorization": "Bearer " + os.environ["PERPLEXITY_API_KEY"]}, tentativas=6)
    a = r["answers"]["rota"]
    tok = r.get("usage", {}).get("input_tokens", 0)
    return a["choice"], a.get("probabilities", {}), time.time() - t, tok * 0.02 / 1e6


def gemini(msg):
    t = time.time()
    r = bancada.post("https://generativelanguage.googleapis.com/v1beta/decisions",
                     {"model": "gemini-decision-1", "input": msg, "questions": perguntas()},
                     {"x-goog-api-key": os.environ["GEMINI_API_KEY"]}, tentativas=6)
    a = r["answers"]["rota"]
    tok = r.get("usage", {}).get("total_input_tokens", 0)
    return a["choice"], a.get("probabilities", {}), time.time() - t, tok * 0.10 / 1e6


ROTEADORES = {
    "palavras": lambda m: (palavras(m), {}, 0.0, 0.0),
    "palavras2": lambda m: (palavras2(m), {}, 0.0, 0.0),
    "pplx-flash": pplx("~perplexity/pplx-decider-flash-latest"),
    "pplx": pplx("~perplexity/pplx-decider-latest"),
    "pplx-direto": pplx_direto,
    "gemini": gemini,
}


def conjunto(lme_amostra):
    """(id, mensagem, rota) for every labelled message."""
    out = []
    A = [d for d in json.load(open(lme_amostra)) if not d["question_id"].endswith("_abs")]
    for d in A:
        out.append(("lme:" + d["question_id"], d["question"], LME_ROTA.get(d["question_id"], "fato")))
    for q in dados.PERGUNTAS:
        out.append(("marta:" + q[0], q[2], MARTA_ROTA.get(q[0], "fato")))
    for i, m in enumerate(NEUTRAS_EN):
        out.append((f"neutra-en:{i}", m, "agora"))
    for i, m in enumerate(NEUTRAS_PT):
        out.append((f"neutra-pt:{i}", m, "agora"))
    return out


def classificar(itens, cache_path):
    cache = {}
    if os.path.exists(cache_path):
        for l in open(cache_path):
            d = json.loads(l)
            cache[(d["roteador"], d["id"])] = d
    trava = threading.Lock()
    tarefas = [(r, i, m) for r in ROTEADORES for i, m, _ in itens if (r, i) not in cache]

    def uma(t):
        r, i, m = t
        try:
            rota, probs, s, custo = ROTEADORES[r](m)
        except Exception as e:  # noqa: BLE001
            print("erro", r, i, str(e)[:160], flush=True)
            return
        d = {"roteador": r, "id": i, "rota": rota, "probs": probs, "s": round(s, 3), "custo": custo}
        with trava:
            cache[(r, i)] = d
            with open(cache_path, "a") as f:
                f.write(json.dumps(d) + "\n")

    with cf.ThreadPoolExecutor(6) as ex:
        list(ex.map(uma, tarefas))
    return cache


def ranquear(binario, paddock, sqlite, linhas, k=8):
    entrada = "".join(f"{p}\t{q.replace(chr(10), ' ')}\n" for p, q in linhas)
    out = subprocess.run([binario, "magma-rank-policy", paddock, sqlite, str(k)], input=entrada,
                         capture_output=True, text=True, encoding="utf-8", check=True).stdout
    return [json.loads(l)["hits"] for l in out.splitlines()]


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--lme-amostra", required=True)
    p.add_argument("--lme-dados", required=True)
    p.add_argument("--marta-dados", required=True)
    p.add_argument("--saida", default=os.path.join(AQUI, "out", "roteador.jsonl"))
    a = p.parse_args()
    binario = bancada.compilar(os.path.join(AQUI, "out"))
    itens = conjunto(a.lme_amostra)
    rotulo = {i: r for i, _, r in itens}
    cache = classificar(itens, a.saida)

    print("## Routing\n")
    print("| router | n | accuracy (4 routes) | gatekeeper: past caught | gatekeeper: false alarms "
          "| `ordem` right | `recencia` right | median latency | cost per 1M messages |")
    print("|---|---|---|---|---|---|---|---|---|")
    for r in ROTEADORES:
        ds = [cache[(r, i)] for i, _, _ in itens if (r, i) in cache]
        n = len(ds)
        ok = sum(1 for d in ds if d["rota"] == rotulo[d["id"]])
        passado = [d for d in ds if rotulo[d["id"]] != "agora"]
        neutro = [d for d in ds if rotulo[d["id"]] == "agora"]
        pegou = sum(1 for d in passado if d["rota"] != "agora")
        alarme = sum(1 for d in neutro if d["rota"] != "agora")
        o = [d for d in ds if rotulo[d["id"]] == "ordem"]
        rc = [d for d in ds if rotulo[d["id"]] == "recencia"]
        lat = sorted(d["s"] for d in ds)
        custo = sum(d["custo"] for d in ds) / max(n, 1) * 1e6
        print(f"| {r} | {n} | {ok}/{n} ({100 * ok / max(n, 1):.0f}%) | {pegou}/{len(passado)} | "
              f"{alarme}/{len(neutro)} | {sum(1 for d in o if d['rota'] == 'ordem')}/{len(o)} | "
              f"{sum(1 for d in rc if d['rota'] == 'recencia')}/{len(rc)} | "
              f"{lat[len(lat) // 2]:.2f} s | ${custo:.2f} |")

    ## Recall's top 8 with each router's policy.
    A = {d["question_id"]: d for d in json.load(open(a.lme_amostra))
         if not d["question_id"].endswith("_abs")}
    print("\n## Recall's top 8 with each router's policy\n")
    print("| router | LongMemEval (60) | of them `ordem` | Marta facts (3 seeds) |")
    print("|---|---|---|---|")
    for r in ROTEADORES:
        pol = lambda i: "temporal" if cache.get((r, i), {}).get("rota") == "recencia" else "default"
        hits_lme, ordem_ok, ordem_n = 0, 0, 0
        for qid, d in A.items():
            pasta = os.path.join(a.lme_dados, qid)
            _, ouro = lm.corpus(d)
            h = ranquear(binario, os.path.join(pasta, "u"), os.path.join(pasta, "magma.sqlite"),
                         [(pol("lme:" + qid), d["question"])])[0]
            ok = any(lm.holds(x, ouro) for x in h)
            hits_lme += ok
            if LME_ROTA.get(qid) == "ordem":
                ordem_n += 1
                ordem_ok += ok
        marta_ok, marta_n = 0, 0
        fatos = [q for q in dados.PERGUNTAS if q[5] != "nunca"]
        for semente in (7, 11, 23):
            base = os.path.join(a.marta_dados, f"s{semente}-m3000")
            linhas = [(pol("marta:" + q[0]), q[2]) for q in fatos]
            todos = ranquear(binario, os.path.join(base, "marta"), os.path.join(base, "magma.sqlite"), linhas)
            for q, h in zip(fatos, todos):
                chaves = q[3] if q[5] != "quando" else ["Lacerda", "cardiolog"]
                marta_n += 1
                marta_ok += any(any(c.lower() in x.lower() for c in chaves) for x in h)
        print(f"| {r} | {hits_lme}/60 | {ordem_ok}/{ordem_n} | {marta_ok}/{marta_n} |", flush=True)


if __name__ == "__main__":
    main()
