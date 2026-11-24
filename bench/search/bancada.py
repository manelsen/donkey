"""Bancada de busca do Donkey: a agente responde perguntas sobre o passado.

Porta de supernova/dev/bancada/bancada.py (mesmo autor), para medir o Donkey
nas mesmas condições: mesmo histórico sintético (agora com sementes), mesmas
perguntas, mesmo juiz. O que é do Donkey vem do próprio Donkey, por
`donkey_bench` (Nim): o prompt de sistema e as 48 ferramentas nativas que um
turno envia, e a `session_search` real (#150/#151). A janela é a do Donkey:
as 20 mensagens mais recentes.

Uso:
  python3 -I bench/search/bancada.py rodar --modelos deepseek --condicoes natural,forcada \\
      --sementes 7,11,23 --saida bench/search/out/base.jsonl
  python3 -I bench/search/bancada.py resumo bench/search/out/base.jsonl

Memória (--memoria):
  md     MEMORY.md com duas notas de perfil, como na bancada da Supernova
  magma  o padrão do Donkey (SQLite): o grafo com uma memória por turno que a
         captura automática guardaria, e a recordação de 8 memórias pela
         pergunta no prompt, como o agente de memória faz a cada mensagem.
         O grafo de cada semente é montado uma vez (embeddings pelo
         OpenRouter) e reaproveitado.

Condições:
  natural  o prompt como o Donkey envia; a agente decide se busca
  forcada  a primeira chamada é obrigatoriamente a session_search: o teto de
           um porteiro perfeito, sem Gemini (todas as perguntas são sobre o
           passado, então um porteiro perfeito sempre dispararia)

Chaves: OPENROUTER_API_KEY e SUPERNOVA_PROVIDER_MISTRAL_API_KEY, lidas de
bench/search/.env.bench ou dos arquivos da Supernova. Nunca impressas.

Cada execução vira uma linha no --saida (o log semeado): semente, modelo,
condição, pergunta, cada chamada de ferramenta com argumentos e saída, a
resposta, o veredito e o motivo do juiz. Uma rodada interrompida continua de
onde parou.
"""

import argparse
import concurrent.futures as cf
import datetime as dt
import json
import os
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

AQUI = os.path.dirname(os.path.abspath(__file__))
RAIZ = os.path.dirname(os.path.dirname(AQUI))
sys.path.insert(0, AQUI)
import dados  # noqa: E402

JANELA = 20           # mensagens recentes que o Donkey mantém (trimTo(20))
MAX_FERRAMENTA = 5    # chamadas de ferramenta por pergunta
FUSO = -180           # o da Marta, minutos
BUSCA = "session_search"


def carregar_env(caminho):
    if not os.path.exists(caminho):
        return
    for linha in open(caminho):
        linha = linha.strip()
        if not linha or linha.startswith("#") or "=" not in linha:
            continue
        k, v = linha.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


for _env in (os.path.join(AQUI, ".env.bench"),
             os.path.expanduser("~/git/supernova-wt/naoachei/.env.bench"),
             os.path.expanduser("~/git/supernova/.env.bench"),
             os.path.expanduser("~/git/supernova/.env")):
    carregar_env(_env)

MODELOS = {
    "deepseek": ("https://api.mistral.ai/v1/chat/completions",
                 "SUPERNOVA_PROVIDER_MISTRAL_API_KEY", "deepseek-v4-1-flash-1017"),
    "nemotron": ("https://openrouter.ai/api/v1/chat/completions",
                 "OPENROUTER_API_KEY", "nvidia/nemotron-3-ultra-550b-a55b:free"),
    "ernie": ("https://openrouter.ai/api/v1/chat/completions",
              "OPENROUTER_API_KEY", "baidu/ernie-5.5-flash-preview:free"),
}


def post(url, corpo, cabecalhos, tentativas=6, timeout=180):
    espera = 5
    for n in range(tentativas):
        try:
            req = urllib.request.Request(
                url, data=json.dumps(corpo).encode(),
                headers={"Content-Type": "application/json", **cabecalhos})
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            texto = e.read().decode(errors="replace")[:300]
            if e.code in (429, 500, 502, 503, 504) and n < tentativas - 1:
                time.sleep(espera)
                espera = min(espera * 2, 120)
                continue
            raise RuntimeError(f"HTTP {e.code}: {texto}")
        except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
            if n < tentativas - 1:
                time.sleep(espera)
                espera = min(espera * 2, 120)
                continue
            raise RuntimeError(f"rede: {e}")


def chat(modelo, mensagens, ferramentas=None, forcar=False):
    url, env, nome = MODELOS[modelo]
    corpo = {"model": nome, "messages": mensagens, "temperature": 0.7}
    if ferramentas:
        corpo["tools"] = ferramentas
        if forcar:
            corpo["tool_choice"] = "any" if "mistral.ai" in url else "required"
    r = post(url, corpo, {"Authorization": "Bearer " + os.environ[env]})
    if "choices" not in r:
        raise RuntimeError("sem choices: " + json.dumps(r)[:300])
    return r["choices"][0]["message"], r.get("usage", {})


# ------------------------------------------------------------------ Donkey


def compilar(saida_dir):
    """Compila o donkey_bench se faltar ou estiver mais velho que o código."""
    binario = os.path.join(saida_dir, "donkey_bench")
    fonte = os.path.join(AQUI, "donkey_bench.nim")
    src = os.path.join(RAIZ, "src")
    mais_novo = max(os.path.getmtime(os.path.join(d, f))
                    for d, _, fs in os.walk(src) for f in fs if f.endswith(".nim"))
    mais_novo = max(mais_novo, os.path.getmtime(fonte))
    if not os.path.exists(binario) or os.path.getmtime(binario) < mais_novo:
        os.makedirs(saida_dir, exist_ok=True)
        subprocess.run(["nim", "c", "-d:release", "--hints:off", "--warnings:off",
                        "-p:" + src, "-o:" + binario, fonte], check=True, cwd=RAIZ)
    return binario


class Donkey:
    """O lado do Donkey: prompt, ferramentas e a session_search real."""

    def __init__(self, binario):
        self.binario = binario
        self.p = subprocess.Popen([binario, "serve"], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.trava = threading.Lock()

    def magma_seed(self, paddock, sqlite, historico):
        if os.path.exists(sqlite + ".pronto"):
            return
        corpus = sqlite + ".corpus.jsonl"
        with open(corpus, "w") as f:
            for g in dados.sessoes(historico):
                sid = f"{g[0]['at']}-1"
                for m in g:
                    f.write(json.dumps({"role": m["role"], "text": m["content"], "ts": m["at"],
                                        "session": sid}, ensure_ascii=False) + "\n")
        if os.path.exists(sqlite):
            os.remove(sqlite)
        out = subprocess.run([self.binario, "magma-seed", paddock, sqlite, corpus],
                             capture_output=True, text=True, encoding="utf-8", check=True).stdout
        open(sqlite + ".pronto", "w").write(out)

    def magma_prompts(self, paddock, sqlite):
        return MagmaPrompts(self.binario, paddock, sqlite)

    def prompt(self, paddock):
        out = subprocess.run([self.binario, "prompt", paddock], capture_output=True,
                             text=True, encoding="utf-8", check=True).stdout
        return json.loads(out)

    def _pedir(self, linha):
        self.p.stdin.write(linha)
        self.p.stdin.flush()
        return self.p.stdout.readline()

    def buscar(self, paddock, args):
        linha = json.dumps({"paddock": paddock, "args": args}, ensure_ascii=False) + "\n"
        with self.trava:
            try:
                resposta = self._pedir(linha)
            except (BrokenPipeError, OSError):
                resposta = ""
            if not resposta:
                ## The helper died: start another, once, so one crash does
                ## not fail every task left in the run.
                self.p = subprocess.Popen([self.binario, "serve"], stdin=subprocess.PIPE,
                                          stdout=subprocess.PIPE, text=True, encoding="utf-8")
                resposta = self._pedir(linha)
            return json.loads(resposta)["out"]


class MagmaPrompts:
    """O prompt de cada pergunta com a recordação do MAGMA (um processo)."""

    def __init__(self, binario, paddock, sqlite):
        self.p = subprocess.Popen([binario, "magma-prompt", paddock, sqlite], stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, text=True, encoding="utf-8")
        self.trava = threading.Lock()
        self.cache = {}

    def para(self, pergunta):
        with self.trava:
            if pergunta not in self.cache:
                self.p.stdin.write(pergunta.replace("\n", " ") + "\n")
                self.p.stdin.flush()
                self.cache[pergunta] = json.loads(self.p.stdout.readline())
            return self.cache[pergunta]


# ------------------------------------------------------------------ agente


def rodar_pergunta(modelo, condicao, pergunta, historico, paddock, donkey, cena):
    if isinstance(cena, MagmaPrompts):
        cena = cena.para(pergunta)
    msgs = [{"role": "system", "content": cena["system"]}]
    for m in historico[-JANELA:]:
        msgs.append({"role": m["role"], "content": m["content"]})
    if msgs[-1]["role"] == "user":
        msgs.append({"role": "assistant", "content": "Entendi."})
    msgs.append({"role": "user", "content": pergunta})
    todas = cena["tools"]
    busca = [t for t in todas if t["function"]["name"] == BUSCA]
    chamadas, uso_total = [], {"prompt": 0, "completion": 0}
    t0 = time.time()
    forcar = condicao == "forcada"
    for _ in range(MAX_FERRAMENTA + 1):
        sem_mais = len(chamadas) >= MAX_FERRAMENTA
        if forcar and not chamadas:
            msg, uso = chat(modelo, msgs, busca, forcar=True)
        else:
            msg, uso = chat(modelo, msgs, None if sem_mais else todas)
        uso_total["prompt"] += uso.get("prompt_tokens", 0) or 0
        uso_total["completion"] += uso.get("completion_tokens", 0) or 0
        tcs = msg.get("tool_calls") or []
        if not tcs:
            return {"resposta": msg.get("content") or "", "chamadas": chamadas,
                    "buscou": any(c["ferramenta"] == BUSCA for c in chamadas),
                    "uso": uso_total, "s": round(time.time() - t0, 1)}
        msgs.append({"role": "assistant", "content": msg.get("content") or "", "tool_calls": tcs})
        for tc in tcs:
            nome = tc["function"]["name"]
            try:
                a = json.loads(tc["function"].get("arguments") or "{}")
            except json.JSONDecodeError:
                a = {}
            out = (donkey.buscar(paddock, a) if nome == BUSCA
                   else "Unavailable in this conversation.")
            chamadas.append({"ferramenta": nome, "args": a, "saida_chars": len(out),
                             "saida": out[:2000]})
            msgs.append({"role": "tool", "tool_call_id": tc.get("id", ""), "name": nome,
                         "content": out})
    return {"resposta": "(limite de chamadas)", "chamadas": chamadas,
            "buscou": any(c["ferramenta"] == BUSCA for c in chamadas),
            "uso": uso_total, "s": round(time.time() - t0, 1)}


# ------------------------------------------------------------------ juiz (o da Supernova)

JUIZ = """Você avalia a resposta de uma agente de companhia a uma pergunta da pessoa sobre algo do passado.

Pergunta da pessoa: {pergunta}
Tipo: {tipo}
{gabarito}

Resposta da agente:
<<<
{resposta}
>>>

Classifique em UMA categoria:
- acertou: {acertou}
- nao_lembra: diz que não lembra, não encontrou ou não tem certeza, sem afirmar conteúdo errado e sem negar que foi dito.
- negou: afirma com certeza que a pessoa nunca disse ou nunca falou disso.
- errou: afirma um conteúdo diferente do gabarito{errado}.
- inventou: afirma conteúdo que nunca foi dito (só para o tipo "nunca", ou quando completa com suposição apresentada como lembrança).

Citar outras coisas que de fato apareceram na conversa (por exemplo, o cachorro da vizinha, consultas de rotina, o chefe pedindo relatório) não é inventar.

Responda só com JSON: {{"categoria": "...", "motivo": "uma frase"}}"""


def carimbo(at):
    t = dt.datetime.fromtimestamp(at / 1000, dt.timezone(dt.timedelta(minutes=FUSO)))
    return t.strftime("%d/%m/%Y %H:%M")


def julgar(q, resposta, historico):
    qid, fid, pergunta, esperado, errado, tipo = q
    if tipo == "nunca":
        gab = "Gabarito: a pessoa NUNCA falou disso na conversa."
        ac = "diz que não lembra ou não encontrou, ou que não falaram disso, sem inventar conteúdo."
    elif tipo == "quando":
        quando = carimbo(dados.data_do_fato(historico, fid))
        gab = (f"Gabarito: foi em {quando}, horário de Brasília (aceite a data certa, com ou sem hora, "
               "a mesma data em UTC, ou uma referência correta como 'em julho').")
        ac = "dá a data certa ou uma referência de tempo compatível."
    else:
        gab = "Gabarito: a resposta certa contém: " + ", ".join(esperado) + "."
        ac = "dá a informação certa do gabarito."
    err = (" (por exemplo: " + ", ".join(errado) + ", que é a versão antiga, corrigida depois)") if errado else ""
    prompt = JUIZ.format(pergunta=pergunta, tipo=tipo, gabarito=gab, resposta=resposta[:3000],
                         acertou=ac, errado=err)
    texto = ""
    for _ in range(3):
        msg, _ = chat("deepseek", [{"role": "user", "content": prompt}])
        texto = (msg.get("content") or "").strip()
        m = re.search(r"\{.*\}", texto, re.S)
        if m:
            try:
                return json.loads(m.group(0))
            except json.JSONDecodeError:
                pass
    return {"categoria": "?", "motivo": texto[:200]}


# ------------------------------------------------------------------ execução


def rodar(args):
    binario = compilar(os.path.join(AQUI, "out"))
    donkey = Donkey(binario)
    perguntas = [q for q in dados.PERGUNTAS if not args.perguntas or q[0] in args.perguntas.split(",")]
    cenas = {}
    for semente in [int(s) for s in args.sementes.split(",")]:
        historico = dados.gerar(args.mensagens, semente)
        paddock = os.path.join(args.dados, f"s{semente}-m{args.mensagens}", "marta")
        nsess = dados.escrever_donkey(paddock, historico)
        if args.memoria == "magma":
            sqlite = os.path.join(os.path.dirname(paddock), "magma.sqlite")
            cenas[semente] = (historico, paddock, sqlite)
        else:
            cenas[semente] = (historico, paddock, donkey.prompt(paddock))
        print(f"semente {semente}: {len(historico)} mensagens em {nsess} sessões", flush=True)
    if args.memoria == "magma":
        ## Os grafos das sementes são montados em paralelo (embeddings são
        ## a parte lenta) e reaproveitados nas rodadas seguintes.
        with cf.ThreadPoolExecutor(len(cenas)) as ex:
            list(ex.map(lambda s: donkey.magma_seed(cenas[s][1], cenas[s][2], cenas[s][0]), cenas))
        for s in cenas:
            h, pad, sqlite = cenas[s]
            print(f"semente {s}: grafo {open(sqlite + '.pronto').read().strip()}", flush=True)
            cenas[s] = (h, pad, donkey.magma_prompts(pad, sqlite))
    tarefas = [(s, mo, c, q, r) for r in range(args.reps) for s in cenas
               for mo in args.modelos.split(",") for c in args.condicoes.split(",") for q in perguntas]
    feitas = set()
    if os.path.exists(args.saida):
        for linha in open(args.saida):
            d = json.loads(linha)
            if d.get("categoria") != "erro":
                feitas.add((d["semente"], d.get("memoria", "md"), d["modelo"], d["condicao"],
                            d["pergunta"], d["rep"]))
    tarefas = [t for t in tarefas
               if (t[0], args.memoria, t[1], t[2], t[3][0], t[4]) not in feitas]
    print(f"{len(tarefas)} tarefas", flush=True)
    os.makedirs(os.path.dirname(os.path.abspath(args.saida)), exist_ok=True)
    trava = threading.Lock()

    def uma(t):
        s, mo, c, q, r = t
        historico, paddock, cena = cenas[s]
        try:
            res = rodar_pergunta(mo, c, q[2], historico, paddock, donkey, cena)
            nota = julgar(q, res["resposta"], historico)
        except Exception as e:  # noqa: BLE001
            res, nota = {"erro": str(e)[:300]}, {"categoria": "erro", "motivo": str(e)[:200]}
        linha = {"semente": s, "memoria": args.memoria, "modelo": mo, "condicao": c, "pergunta": q[0], "tipo": q[5], "rep": r,
                 "categoria": nota.get("categoria"), "motivo": nota.get("motivo"), **res}
        with trava:
            with open(args.saida, "a") as f:
                f.write(json.dumps(linha, ensure_ascii=False) + "\n")
            print(f"s{s:<3} {mo:9} {c:8} {q[0]:15} r{r} -> {linha['categoria']}"
                  f"{' (buscou)' if linha.get('buscou') else ''}", flush=True)

    with cf.ThreadPoolExecutor(args.paralelo) as ex:
        list(ex.map(uma, tarefas))


def resumo(args):
    from collections import defaultdict
    ## A resumed run appends a new line for a task that failed before; the
    ## last line of each task is the one that counts.
    ultima = {}
    for l in open(args.arquivo):
        d = json.loads(l)
        ultima[(d.get("semente"), d.get("memoria", "md"), d["modelo"], d["condicao"],
                d["pergunta"], d["rep"])] = d
    L = list(ultima.values())
    erros = sum(1 for d in L if d.get("categoria") == "erro")
    L = [d for d in L if d.get("categoria") != "erro"]

    def tabela(chave, titulo):
        g = defaultdict(list)
        for d in L:
            g[chave(d)].append(d)
        print(f"\n### {titulo}\n")
        print("| grupo | n | buscou | **acertou** | acertou buscando | não lembra | negou | errou | inventou |")
        print("|---|---|---|---|---|---|---|---|---|")
        for k in sorted(g, key=str):
            ds = g[k]
            n = len(ds)
            c = lambda cat: sum(1 for d in ds if d["categoria"] == cat)
            pc = lambda x: f"{100 * x / n:.0f}%"
            print(f"| {' / '.join(map(str, k))} | {n} | {pc(sum(1 for d in ds if d.get('buscou')))} | "
                  f"**{pc(c('acertou'))}** | {pc(sum(1 for d in ds if d['categoria'] == 'acertou' and d.get('buscou')))} | "
                  f"{pc(c('nao_lembra'))} | {pc(c('negou'))} | {pc(c('errou'))} | {pc(c('inventou'))} |")

    mem = lambda d: d.get("memoria", "md")
    tabela(lambda d: (mem(d), d["modelo"], d["condicao"]), "Por memória, modelo e condição (todas as sementes)")
    tabela(lambda d: (mem(d), d["modelo"], d["condicao"], f"s{d['semente']}"), "Por semente")
    tabela(lambda d: (mem(d), d["condicao"], d["tipo"]), "Por tipo de pergunta")
    tabela(lambda d: (mem(d), d["condicao"], d["pergunta"]), "Por pergunta")
    print(f"\n(execuções com erro, fora das tabelas: {erros})")


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("rodar")
    r.add_argument("--modelos", default="deepseek")
    r.add_argument("--condicoes", default="natural,forcada")
    r.add_argument("--sementes", default="7,11,23")
    r.add_argument("--perguntas", default="")
    r.add_argument("--memoria", choices=["md", "magma"], default="md")
    r.add_argument("--reps", type=int, default=1)
    r.add_argument("--mensagens", type=int, default=3000)
    r.add_argument("--paralelo", type=int, default=6)
    r.add_argument("--dados", default="/tmp/donkey-bancada")
    r.add_argument("--saida", required=True)
    s = sub.add_parser("resumo")
    s.add_argument("arquivo")
    a = p.parse_args()
    {"rodar": rodar, "resumo": resumo}[a.cmd](a)


if __name__ == "__main__":
    main()
