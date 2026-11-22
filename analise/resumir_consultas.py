"""Resume os CSVs de analise/medir_consultas.sh em tabelas Markdown.

Uso: python3 analise/resumir_consultas.py [docs/evidencias/consultas/*.csv]
Sem argumentos, lê todos os CSVs de docs/evidencias/consultas/ e grava o resultado
também em docs/evidencias/consultas/resumo.md.

Para cada (rótulo, n, estratégia): nº de SQL (é o mesmo em toda repetição), mediana do
tempo no servidor (X-Elapsed-Ms), mediana do tempo gasto no banco (X-SQL-Ms) e tamanho do JSON.
Só a biblioteca padrão é usada.
"""

import csv
import statistics
import sys
from collections import defaultdict
from pathlib import Path

RAIZ = Path(__file__).resolve().parent.parent
DIR = RAIZ / "docs" / "evidencias" / "consultas"

ORDEM = ["lazy", "eager", "join-fetch", "entity-graph", "batch", "dto", "nativo",
         "join-fetch-paginacao-memoria"]


def carregar(arquivos):
    grupos = defaultdict(list)
    for arq in arquivos:
        with open(arq, newline="", encoding="utf-8") as f:
            for linha in csv.DictReader(f):
                chave = (linha["rotulo"], int(linha["n"]), linha["estrategia"])
                grupos[chave].append(linha)
    return grupos


def faixa(valores):
    """Mediana e, se houver variação, o intervalo mín–máx."""
    med = statistics.median(valores)
    lo, hi = min(valores), max(valores)
    texto = f"{med:g}"
    if lo != hi:
        texto += f" ({lo:g}–{hi:g})"
    return texto


def tabela(grupos):
    linhas = []
    rotulos = sorted({k[0] for k in grupos}, key=lambda r: (r != "sem-indice", r))
    for rotulo in rotulos:
        for n in sorted({k[1] for k in grupos if k[0] == rotulo}):
            linhas.append(f"\n### {rotulo} · n = {n}\n")
            linhas.append("| Estratégia | Nº de SQL | Tempo no servidor (ms) | Tempo no banco (ms) | JSON (bytes) | Repetições |")
            linhas.append("|---|---:|---:|---:|---:|---:|")
            presentes = [e for e in ORDEM if (rotulo, n, e) in grupos]
            presentes += sorted(e for (r, nn, e) in grupos if r == rotulo and nn == n and e not in ORDEM)
            for e in presentes:
                g = grupos[(rotulo, n, e)]
                sql = sorted({int(x["sql_count"]) for x in g})
                elapsed = [float(x["elapsed_ms"]) for x in g]
                sql_ms = [float(x["sql_ms"]) for x in g]
                tamanho = sorted({int(x["bytes"]) for x in g})
                linhas.append(
                    f"| {e} | {'/'.join(map(str, sql))} | {faixa(elapsed)} | {faixa(sql_ms)} "
                    f"| {'/'.join(map(str, tamanho))} | {len(g)} |")
    return "\n".join(linhas).lstrip("\n")


def main():
    arquivos = [Path(a) for a in sys.argv[1:]] or sorted(DIR.glob("*.csv"))
    if not arquivos:
        sys.exit("Nenhum CSV encontrado. Rode antes analise/medir_consultas.sh <rotulo>.")
    md = tabela(carregar(arquivos))
    print(md)
    if not sys.argv[1:]:
        cabecalho = ("# Resumo das medições do Item 2\n\n"
                     "Gerado por `analise/resumir_consultas.py` a partir dos CSVs desta pasta. "
                     "Tempos em mediana (mín–máx).\n\n")
        (DIR / "resumo.md").write_text(cabecalho + md + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
