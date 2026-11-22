#!/usr/bin/env bash
# Mede os endpoints de comparação do Item 2 (/api/pedidos/*) e grava um CSV com cada execução.
#
# Uso: ./analise/medir_consultas.sh <rotulo>          (ex.: sem-indice, com-indice)
#
# Para cada n e cada estratégia: AQUECIMENTO chamadas descartadas e REPETICOES chamadas medidas.
# Cada linha do CSV traz o que a própria resposta informa (X-SQL-Count, X-SQL-Ms, X-Elapsed-Ms),
# o tempo total visto pelo cliente (curl) e o tamanho do JSON.
# Pré-requisito: a API rodando em $BASE_URL. Resumo: python3 analise/resumir_consultas.py
set -euo pipefail
export LC_ALL=C   # ponto decimal no awk/printf, independente do idioma do sistema

ROTULO="${1:?informe um rótulo, ex.: sem-indice ou com-indice}"
BASE_URL="${BASE_URL:-http://localhost:8080}"
NS="${NS:-10 100 1000}"
ESTRATEGIAS="${ESTRATEGIAS:-lazy eager join-fetch entity-graph batch dto nativo join-fetch-paginacao-memoria}"
AQUECIMENTO="${AQUECIMENTO:-1}"
REPETICOES="${REPETICOES:-3}"

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SAIDA="$RAIZ/docs/evidencias/consultas"
mkdir -p "$SAIDA"
CSV="$SAIDA/$ROTULO.csv"
CABECALHOS="$(mktemp)"
trap 'rm -f "$CABECALHOS"' EXIT

curl -sf "$BASE_URL/actuator/health" > /dev/null || { echo "API fora do ar em $BASE_URL" >&2; exit 1; }

echo "rotulo,estrategia,n,repeticao,sql_count,sql_ms,elapsed_ms,cliente_ms,bytes,http" > "$CSV"

for n in $NS; do
    for e in $ESTRATEGIAS; do
        for ((r = 1 - AQUECIMENTO; r <= REPETICOES; r++)); do
            medida=$(curl -s -o /dev/null -D "$CABECALHOS" \
                -w '%{time_total} %{size_download} %{http_code}' "$BASE_URL/api/pedidos/$e?n=$n")
            ((r < 1)) && continue
            read -r total bytes http <<< "$medida"
            cab() { grep -i "^$1:" "$CABECALHOS" | tr -d '\r' | awk '{print $2}'; }
            cliente_ms=$(awk -v t="$total" 'BEGIN {printf "%.1f", t * 1000}')
            echo "$ROTULO,$e,$n,$r,$(cab X-SQL-Count),$(cab X-SQL-Ms),$(cab X-Elapsed-Ms),$cliente_ms,$bytes,$http" >> "$CSV"
        done
        echo "n=$n $e: ok"
    done
done

echo "CSV em ${CSV#"$RAIZ"/}"
