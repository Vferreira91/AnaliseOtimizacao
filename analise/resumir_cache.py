"""Resume docs/evidencias/cache/medicoes.csv (gerado por analise/medir_cache.sh) em Markdown.

Uso: python3 analise/resumir_cache.py docs/evidencias/cache/medicoes.csv
Só a biblioteca padrão é usada.
"""

import csv
import statistics
import sys
from collections import Counter, defaultdict

ORDEM = ["produto-sem", "produto-miss", "produto-hit",
         "relatorio-sem", "relatorio-miss", "relatorio-hit"]


def p95(valores):
    ordenados = sorted(valores)
    return ordenados[max(0, round(0.95 * len(ordenados)) - 1)]


def main():
    grupos = defaultdict(list)
    with open(sys.argv[1], newline="", encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            grupos[linha["variante"]].append(linha)

    print("# Cache: custo por requisição (um cliente, sem concorrência)\n")
    print("Gerado por `analise/medir_cache.sh` + `analise/resumir_cache.py`. "
          "Tempos no servidor (`X-Elapsed-Ms`) e no cliente (curl), em ms.\n")
    print("| Variante | Requisições | X-Cache | SQL/req | Servidor: média | mediana | p95 "
          "| Banco (média) | Cliente: mediana |")
    print("|---|---:|---|---:|---:|---:|---:|---:|---:|")
    for v in [v for v in ORDEM if v in grupos]:
        g = grupos[v]
        elapsed = [float(x["elapsed_ms"]) for x in g]
        sql_ms = [float(x["sql_ms"]) for x in g]
        cliente = [float(x["cliente_ms"]) for x in g]
        sql = statistics.mean(int(x["sql_count"]) for x in g)
        status = ", ".join(f"{k} {n}" for k, n in Counter(x["x_cache"] for x in g).items())
        print(f"| {v} | {len(g)} | {status} | {sql:g} | {statistics.mean(elapsed):.2f} "
              f"| {statistics.median(elapsed):.2f} | {p95(elapsed):.2f} "
              f"| {statistics.mean(sql_ms):.2f} | {statistics.median(cliente):.2f} |")


if __name__ == "__main__":
    main()
