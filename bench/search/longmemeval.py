"""Recall depth on LongMemEval S: is the answer in Donkey's recall?

D. Wu et al., LongMemEval, ICLR 2025, arXiv:2410.10813. Data (MIT):
https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned. The sample is
Supernova's (dev/bancada/longmemeval.py): 10 questions of each type plus 30
abstentions, random.Random(11); only the 60 answerable ones are measured.

No LLM. For each question, its haystack becomes a MAGMA SQLite graph the way
Donkey's automatic capture would fill it: one memory per user turn and its
reply (capture rules applied), embedded with qwen3-embedding-8b, stamped with
the session's date. Then Donkey's recall ranks the memories for the question
(`magma-rank`, the same search the memory agent calls with 8), and the script
records where the first memory holding the answer (a turn marked
`has_answer`) lands: inside the top 8, 16, 40, or not at all.

  python3 -I bench/search/longmemeval.py amostra.json out/lme.jsonl \\
      --dados /tmp/donkey-lme --paralelo 8
  python3 -I bench/search/longmemeval.py resumo out/lme.jsonl
"""
import argparse, concurrent.futures as cf, datetime as dt, json, os, re, subprocess, sys, threading

AQUI = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, AQUI)
import bancada  # noqa: E402  (keys and the helper's build)

K = 40


def ts_ms(data):
    ## "2023/04/25 (Tue) 10:21", UTC; the weekday is optional.
    texto = re.sub(r"\s*\([^)]*\)\s*", " ", data).strip()
    d = dt.datetime.strptime(texto, "%Y/%m/%d %H:%M")
    return int(d.replace(tzinfo=dt.timezone.utc).timestamp() * 1000)


def corpus(d):
    """Lines for `magma-seed` and, per captured turn, whether it holds the answer."""
    linhas, ouro = [], []
    for sid, data, sess in zip(d["haystack_session_ids"], d["haystack_dates"], d["haystack_sessions"]):
        base = ts_ms(data)
        for k, t in enumerate(sess):
            linhas.append({"role": t["role"], "text": t["content"], "ts": base + k * 60000, "session": sid})
            if t.get("has_answer"):
                ouro.append(t["content"])
    return linhas, ouro


def holds(memoria, ouro):
    ## A captured memory holds a gold turn when it contains its first 120
    ## characters (capture clips each side at 4000 characters).
    ## An empty gold turn would be "in" every memory: it is not a match.
    return any(g.strip() and g.strip()[:120] in memoria for g in ouro)


def uma(d, binario, base):
    linhas, ouro = corpus(d)
    pasta = os.path.join(base, d["question_id"])
    paddock = os.path.join(pasta, "u")
    os.makedirs(paddock, exist_ok=True)
    sqlite = os.path.join(pasta, "magma.sqlite")
    cpath = os.path.join(pasta, "corpus.jsonl")
    if not (os.path.exists(sqlite) and os.path.exists(sqlite + ".pronto")):
        with open(cpath, "w") as f:
            for l in linhas:
                f.write(json.dumps(l, ensure_ascii=False) + "\n")
        for nome in ("USER.md", "MEMORY.md", "PREFERENCES.md"):
            open(os.path.join(paddock, nome), "w").close()
        if os.path.exists(sqlite):
            os.remove(sqlite)
        out = subprocess.run([binario, "magma-seed", paddock, sqlite, cpath], capture_output=True,
                             text=True, encoding="utf-8", check=True).stdout
        with open(sqlite + ".pronto", "w") as f:
            f.write(out)
    r = subprocess.run([binario, "magma-rank", paddock, sqlite, str(K)],
                       input=d["question"].replace("\n", " ") + "\n", capture_output=True,
                       text=True, encoding="utf-8", check=True).stdout
    hits = json.loads(r)["hits"]
    pos = next((i + 1 for i, h in enumerate(hits) if holds(h, ouro)), None)
    ## Was the answer captured at all? (a trivial user turn is skipped)
    seed = json.load(open(sqlite + ".pronto"))
    return {"id": d["question_id"], "tipo": d["question_type"], "rank": pos,
            "memorias": seed.get("stored"), "ouro_turnos": len(ouro)}


def rodar(a):
    binario = bancada.compilar(os.path.join(AQUI, "out"))
    A = [d for d in json.load(open(a.amostra)) if not d["question_id"].endswith("_abs")]
    feitos = set()
    if os.path.exists(a.saida):
        feitos = {json.loads(l)["id"] for l in open(a.saida)}
    pend = [d for d in A if d["question_id"] not in feitos]
    print(f"{len(pend)} pendentes de {len(A)}", flush=True)
    trava = threading.Lock()

    def uma_segura(d):
        try:
            r = uma(d, binario, a.dados)
        except Exception as e:  # noqa: BLE001
            print("erro", d["question_id"], str(e)[:200], flush=True)
            return
        with trava:
            with open(a.saida, "a") as f:
                f.write(json.dumps(r) + "\n")
            print(r["id"], r["tipo"], "rank", r["rank"], flush=True)

    with cf.ThreadPoolExecutor(a.paralelo) as ex:
        list(ex.map(uma_segura, pend))


def resumo(a):
    from collections import defaultdict
    L = [json.loads(l) for l in open(a.arquivo)]
    g = defaultdict(list)
    for d in L:
        g[d["tipo"]].append(d)
    g["(all)"] = L
    print("| type | n | top 1 | top 8 | top 16 | top 40 | not in 40 |\n|---|---|---|---|---|---|---|")
    for k in sorted(g):
        ds = g[k]
        n = len(ds)
        em = lambda c: sum(1 for d in ds if d["rank"] and d["rank"] <= c)
        print(f"| {k} | {n} | {em(1)} | {em(8)} | {em(16)} | {em(40)} | {n - em(40)} |")
    ranks = sorted(d["rank"] for d in L if d["rank"])
    if ranks:
        print(f"\nworst rank found: {ranks[-1]}; median {ranks[len(ranks) // 2]}")


def main():
    p = argparse.ArgumentParser()
    if len(sys.argv) > 1 and sys.argv[1] == "resumo":
        p.add_argument("cmd")
        p.add_argument("arquivo")
        resumo(p.parse_args())
        return
    p.add_argument("amostra")
    p.add_argument("saida")
    p.add_argument("--dados", default="/tmp/donkey-lme")
    p.add_argument("--paralelo", type=int, default=8)
    rodar(p.parse_args())


if __name__ == "__main__":
    main()
