"""Tabelas e gráficos de uma rodada de testes de carga (k6/rodar.sh).

Uso:
    analise/.venv/bin/python analise/gerar_graficos.py k6/resultados/<rodada> [--destino DIR]

Lê os JSONs do k6 (fase de coleta) e as amostras de `docker stats`, agrega as repetições de
cada (variante, VUs) e grava em DIR (padrão: <rodada>/relatorio):
    resumo.csv     uma linha por (variante, VUs), com média entre repetições e faixa mín–máx
    resumo.md      tabelas por cenário, prontas para o README
    graficos/*.png um painel por cenário: latência p95, throughput e taxa de erros × VUs

Os números vêm só das execuções; nada é estimado. Cores: paleta categórica de referência da
skill de dataviz (ordem fixa, slots 1–4), com rótulos diretos porque três slots ficam abaixo
de 3:1 de contraste no fundo claro.
"""

import argparse
import csv
import json
import statistics
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
from matplotlib.ticker import FuncFormatter  # noqa: E402

GRUPOS = [
    ("c1-produto", "C1 · Produto por id: sem cache × com cache",
     ["produto-sem", "produto-com-frio", "produto-com-quente"]),
    ("c1-relatorio", "C1 · Relatório de vendas por categoria: sem cache × com cache",
     ["relatorio-sem", "relatorio-com"]),
    ("c2-persistencia", "C2 · 50 pedidos com cliente e itens, por estratégia de carregamento",
     ["pedidos-lazy", "pedidos-eager", "pedidos-join-fetch", "pedidos-dto"]),
    ("c3-indice", "C3 · Pedidos de um cliente (Q1): sem índice × com índice",
     ["cliente-pedidos-sem-indice", "cliente-pedidos-com-indice"]),
]

ROTULOS = {
    "produto-sem": "sem cache",
    "produto-com-frio": "com cache (frio)",
    "produto-com-quente": "com cache (quente)",
    "relatorio-sem": "sem cache",
    "relatorio-com": "com cache",
    "pedidos-lazy": "LAZY",
    "pedidos-eager": "EAGER",
    "pedidos-join-fetch": "JOIN FETCH",
    "pedidos-dto": "DTO",
    "cliente-pedidos-sem-indice": "sem índice",
    "cliente-pedidos-com-indice": "com índice",
}

# Paleta e tinta (modo claro) da paleta de referência da skill de dataviz.
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100"]
SUPERFICIE = "#fcfcfb"
TINTA = "#0b0b0b"
TINTA_SEC = "#52514e"
MUDO = "#898781"
GRADE = "#e1e0d9"
EIXO = "#c3c2b7"


# --------------------------------------------------------------------------- dados

def cpu_media(dir_rodada: Path, ident: str, aquecimento_s: float, coleta_s: float):
    """CPU média (%) de cada container durante a janela de coleta."""
    tempo = dir_rodada / f"{ident}.tempo"
    stats = dir_rodada / f"{ident}.stats.csv"
    if not tempo.exists() or not stats.exists():
        return {}
    inicio = float(tempo.read_text().split("=", 1)[1]) + aquecimento_s
    fim = inicio + coleta_s
    por_container = defaultdict(list)
    with open(stats, newline="", encoding="utf-8") as f:
        for linha in csv.DictReader(f):
            if inicio <= float(linha["epoch"]) <= fim:
                por_container[linha["container"]].append(float(linha["cpu_pct"]))
    return {c: statistics.mean(v) for c, v in por_container.items() if v}


def taxa_hit(cache_hit):
    """% de HIT; None quando o endpoint não usa cache (só respostas BYPASS, sem amostras)."""
    if not cache_hit or (cache_hit.get("passes", 0) + cache_hit.get("fails", 0)) == 0:
        return None
    return cache_hit["rate"] * 100


def carregar(dir_rodada: Path):
    execucoes = defaultdict(list)
    for arq in sorted(dir_rodada.glob("*_r*.json")):
        d = json.loads(arq.read_text(encoding="utf-8"))
        aquec = float(d["inicio_coleta_offset_s"])
        cpu = cpu_media(dir_rodada, arq.stem, aquec, float(d["coleta_s"]))
        lat = d.get("latencia_ms") or {}
        execucoes[(d["variante"], int(d["vus"]))].append({
            "throughput": d["throughput_rps"],
            "media": lat.get("avg"),
            "p95": lat.get("p(95)"),
            "p99": lat.get("p(99)"),
            "erros": (d.get("taxa_erros") or 0.0) * 100,
            "requisicoes": d["requisicoes"],
            "hit": taxa_hit(d.get("cache_hit")),
            "sql": d["sql_por_req"]["avg"] if d.get("sql_por_req") else None,
            "cpu_app": cpu.get("ao-app"),
            "cpu_pg": cpu.get("ao-postgres"),
        })
    return execucoes


def agregar(execucoes):
    """Média entre repetições (e mín/máx das métricas principais)."""
    linhas = []
    for (variante, vus), runs in sorted(execucoes.items()):
        def media(campo):
            vals = [r[campo] for r in runs if r[campo] is not None]
            return statistics.mean(vals) if vals else None

        def faixa(campo):
            vals = [r[campo] for r in runs if r[campo] is not None]
            return (min(vals), max(vals)) if vals else (None, None)

        linha = {"variante": variante, "vus": vus, "repeticoes": len(runs)}
        for campo in ("throughput", "media", "p95", "p99", "erros", "requisicoes", "hit", "sql",
                      "cpu_app", "cpu_pg"):
            linha[campo] = media(campo)
        linha["p95_min"], linha["p95_max"] = faixa("p95")
        linha["throughput_min"], linha["throughput_max"] = faixa("throughput")
        linhas.append(linha)
    return linhas


# --------------------------------------------------------------------------- saída

def fmt(v, casas=1):
    return "–" if v is None else f"{v:,.{casas}f}".replace(",", "_").replace(".", ",").replace("_", ".")


def gravar_csv(linhas, destino: Path):
    campos = ["variante", "vus", "repeticoes", "throughput", "throughput_min", "throughput_max",
              "media", "p95", "p95_min", "p95_max", "p99", "erros", "requisicoes", "hit", "sql",
              "cpu_app", "cpu_pg"]
    with open(destino / "resumo.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=campos)
        w.writeheader()
        for linha in linhas:
            w.writerow({k: ("" if linha[k] is None else (round(linha[k], 3) if isinstance(linha[k], float) else linha[k]))
                        for k in campos})


def gravar_md(linhas, destino: Path, dir_rodada: Path):
    por_var = defaultdict(list)
    for linha in linhas:
        por_var[linha["variante"]].append(linha)
    partes = [f"# Testes de carga: rodada `{dir_rodada.name}`\n"]
    info = dir_rodada / "rodada.txt"
    if info.exists():
        partes.append("```\n" + info.read_text(encoding="utf-8").strip() + "\n```\n")
    partes.append("Média entre repetições; entre parênteses, mín–máx das repetições. "
                  "Latências em ms (medidas pelo k6, no cliente). CPU = média do `docker stats` "
                  "na fase de coleta (100% = 1 núcleo).\n")
    for chave, titulo, variantes in GRUPOS:
        presentes = [v for v in variantes if v in por_var]
        if not presentes:
            continue
        partes.append(f"\n## {titulo}\n")
        partes.append(f"![{titulo}](graficos/{chave}.png)\n")
        partes.append("| Variante | VUs | Req/s | Média | p95 | p99 | Erros (%) | HIT (%) | SQL/req | CPU app (%) | CPU Postgres (%) |")
        partes.append("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for v in presentes:
            for l in sorted(por_var[v], key=lambda x: x["vus"]):
                thr = fmt(l["throughput"])
                p95 = fmt(l["p95"])
                if l["repeticoes"] > 1:
                    thr += f" ({fmt(l['throughput_min'], 0)}–{fmt(l['throughput_max'], 0)})"
                    p95 += f" ({fmt(l['p95_min'])}–{fmt(l['p95_max'])})"
                partes.append(
                    f"| {ROTULOS.get(v, v)} | {l['vus']} | {thr} | {fmt(l['media'])} | {p95} "
                    f"| {fmt(l['p99'])} | {fmt(l['erros'], 2)} | {fmt(l['hit'])} | {fmt(l['sql'], 2)} "
                    f"| {fmt(l['cpu_app'], 0)} | {fmt(l['cpu_pg'], 0)} |")
    (destino / "resumo.md").write_text("\n".join(partes) + "\n", encoding="utf-8")


def estilo_eixo(ax, titulo):
    ax.set_facecolor(SUPERFICIE)
    ax.set_title(titulo, loc="left", fontsize=10, color=TINTA, pad=8)
    for lado in ("top", "right", "left"):
        ax.spines[lado].set_visible(False)
    ax.spines["bottom"].set_color(EIXO)
    ax.tick_params(colors=MUDO, labelsize=8, length=0)
    ax.grid(axis="y", color=GRADE, linewidth=0.6)
    ax.set_axisbelow(True)
    ax.set_xlabel("usuários virtuais simultâneos (VUs)", fontsize=8, color=TINTA_SEC)


def rotular_fim_das_linhas(ax, fig, pontos, fonte_pt=8):
    """Rótulo direto no fim de cada linha, em tinta de texto (não na cor da série).

    Rótulos de linhas que terminam perto umas das outras são afastados na vertical até ficarem
    a pelo menos 1,3 linha de texto de distância, para não se sobreporem.
    """
    pontos = [(r, x, y) for r, x, y in pontos if y is not None]
    if not pontos:
        return
    espaco_px = fonte_pt * 1.3 * fig.dpi / 72
    fig.canvas.draw()  # fixa os limites dos eixos antes de converter para pixels
    em_px = sorted(((ax.transData.transform((x, y))[1], r, x, y) for r, x, y in pontos))
    ajustados = []
    for ypx, rotulo, x, y in em_px:
        if ajustados and ypx - ajustados[-1][0] < espaco_px:
            ypx = ajustados[-1][0] + espaco_px
        ajustados.append((ypx, rotulo, x, y))
    for ypx, rotulo, x, y in ajustados:
        original = ax.transData.transform((x, y))[1]
        deslocamento_pt = (ypx - original) * 72 / fig.dpi
        ax.annotate(rotulo, (x, y), xytext=(6, deslocamento_pt), textcoords="offset points",
                    va="center", fontsize=fonte_pt, color=TINTA_SEC)


def grafico_grupo(linhas, chave, titulo, variantes, destino: Path):
    por_var = defaultdict(list)
    for linha in linhas:
        if linha["variante"] in variantes:
            por_var[linha["variante"]].append(linha)
    presentes = [v for v in variantes if v in por_var]
    if not presentes:
        return None

    fig, eixos = plt.subplots(1, 3, figsize=(13, 4.2), dpi=150)
    fig.patch.set_facecolor(SUPERFICIE)
    paineis = [
        ("p95", "Latência p95 (ms, escala log)", True),
        ("throughput", "Throughput (req/s)", False),
        ("erros", "Taxa de erros (%)", False),
    ]
    todos_vus = sorted({l["vus"] for v in presentes for l in por_var[v]})
    for ax, (campo, subtitulo, log) in zip(eixos, paineis):
        estilo_eixo(ax, subtitulo)
        for i, v in enumerate(presentes):
            pts = sorted(por_var[v], key=lambda x: x["vus"])
            xs = [p["vus"] for p in pts]
            ys = [p[campo] for p in pts]
            cor = SERIES[i]
            ax.plot(xs, ys, color=cor, linewidth=2, marker="o", markersize=5,
                    markeredgecolor=SUPERFICIE, markeredgewidth=1.2, label=ROTULOS.get(v, v), zorder=3)
            if campo in ("p95", "throughput") and all(p["repeticoes"] > 1 for p in pts):
                ax.fill_between(xs, [p[f"{campo}_min"] for p in pts], [p[f"{campo}_max"] for p in pts],
                                color=cor, alpha=0.15, linewidth=0, zorder=2)
        if log:
            ax.set_yscale("log")
            ax.yaxis.set_major_formatter(FuncFormatter(lambda y, _: f"{y:g}"))
        else:
            ax.set_ylim(bottom=0)
        if campo == "erros" and ax.get_ylim()[1] < 1:
            ax.set_ylim(0, 1)
        ax.set_xticks(todos_vus)
        ax.set_xlim(0, max(todos_vus) * 1.18)
        if campo == "p95":
            rotular_fim_das_linhas(ax, fig, [
                (ROTULOS.get(v, v), max(p["vus"] for p in por_var[v]),
                 max(por_var[v], key=lambda p: p["vus"])["p95"]) for v in presentes])
    fig.suptitle(titulo, x=0.01, ha="left", fontsize=12, color=TINTA)
    handles, labels = eixos[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper right", ncol=len(presentes), frameon=False,
               fontsize=9, labelcolor=TINTA_SEC, bbox_to_anchor=(0.99, 0.99))
    fig.tight_layout(rect=(0, 0, 1, 0.93))
    caminho = destino / "graficos" / f"{chave}.png"
    fig.savefig(caminho, facecolor=SUPERFICIE)
    plt.close(fig)
    return caminho


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rodada", type=Path, help="pasta da rodada em k6/resultados/")
    ap.add_argument("--destino", type=Path, help="onde gravar (padrão: <rodada>/relatorio)")
    args = ap.parse_args()

    execucoes = carregar(args.rodada)
    if not execucoes:
        raise SystemExit(f"Nenhum resultado em {args.rodada}")
    destino = args.destino or (args.rodada / "relatorio")
    (destino / "graficos").mkdir(parents=True, exist_ok=True)

    linhas = agregar(execucoes)
    gravar_csv(linhas, destino)
    gravar_md(linhas, destino, args.rodada)
    for chave, titulo, variantes in GRUPOS:
        caminho = grafico_grupo(linhas, chave, titulo, variantes, destino)
        if caminho:
            print(f"gráfico: {caminho}")
    print(f"tabelas: {destino / 'resumo.md'}")


if __name__ == "__main__":
    main()
