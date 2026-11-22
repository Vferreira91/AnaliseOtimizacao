#!/usr/bin/env bash
# Mede, requisição a requisição (um cliente, sem concorrência), o custo de cada situação do cache:
#
#   produto-sem       GET /api/produtos/{id}/sem-cache                    (sempre no banco)
#   produto-miss      GET /api/produtos/{id}/com-cache com o cache vazio  (banco + gravação no Redis)
#   produto-hit       GET /api/produtos/{id}/com-cache já no cache         (só Redis)
#   relatorio-sem / relatorio-miss / relatorio-hit   idem para o relatório de vendas
#
# Os ids de produto são sorteados com semente fixa (os mesmos em toda execução). No MISS o cache é
# esvaziado (DELETE /api/admin/cache) antes de cada requisição; essa limpeza não entra na medida.
# A concorrência fica para os testes de carga (Fase 4).
#
# Pré-requisito: API rodando com o profile padrão (TTL de 10 min / 60 s).
# Uso: ./analise/medir_cache.sh    -> docs/evidencias/cache/medicoes.csv e resumo.md
set -euo pipefail
export LC_ALL=C

BASE_URL="${BASE_URL:-http://localhost:8080}"
N_PRODUTO="${N_PRODUTO:-200}"
N_RELATORIO_BANCO="${N_RELATORIO_BANCO:-20}"   # sem cache e MISS: ~1 s cada
N_RELATORIO_HIT="${N_RELATORIO_HIT:-200}"
AQUECIMENTO="${AQUECIMENTO:-20}"

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SAIDA="$RAIZ/docs/evidencias/cache"
mkdir -p "$SAIDA"
CSV="$SAIDA/medicoes.csv"
CAB="$(mktemp)"
trap 'rm -f "$CAB"; curl -s -X DELETE "$BASE_URL/api/admin/cache" > /dev/null || true' EXIT

curl -sf "$BASE_URL/actuator/health" > /dev/null || { echo "API fora do ar em $BASE_URL" >&2; exit 1; }

limpar() { curl -s -X DELETE "$BASE_URL/api/admin/cache" > /dev/null; }

# medir <variante> <caminho>: uma requisição, uma linha no CSV.
medir() {
    local variante="$1" caminho="$2" medida
    medida=$(curl -s -o /dev/null -D "$CAB" -w '%{time_total} %{http_code}' "$BASE_URL$caminho")
    read -r total http <<< "$medida"
    c() { grep -i "^$1:" "$CAB" | tr -d '\r' | awk '{print $2}'; }
    echo "$variante,$caminho,$(c X-Cache),$(c X-SQL-Count),$(c X-SQL-Ms),$(c X-Elapsed-Ms),$(awk -v t="$total" 'BEGIN {printf "%.2f", t * 1000}'),$http" >> "$CSV"
}

IDS=$(python3 -I -c "import random; random.seed(7); print(*random.sample(range(1, 20001), $N_PRODUTO))")
REL="/api/relatorios/vendas-por-categoria"

echo "variante,caminho,x_cache,sql_count,sql_ms,elapsed_ms,cliente_ms,http" > "$CSV"

echo "Aquecendo a JVM ($AQUECIMENTO requisições de cada tipo)..."
for ((i = 1; i <= AQUECIMENTO; i++)); do
    curl -s -o /dev/null "$BASE_URL/api/produtos/$i/sem-cache"
    curl -s -o /dev/null "$BASE_URL/api/produtos/$i/com-cache"
done
curl -s -o /dev/null "$BASE_URL$REL/sem-cache"
curl -s -o /dev/null "$BASE_URL$REL/com-cache"

echo "produto-sem";  for id in $IDS; do medir produto-sem "/api/produtos/$id/sem-cache"; done
echo "produto-miss"; for id in $IDS; do limpar; medir produto-miss "/api/produtos/$id/com-cache"; done
echo "produto-hit"
# O passo MISS esvazia o cache antes de cada requisição; preenche todos os ids (sem medir)
# e só então mede as leituras, que devem ser todas HIT.
for id in $IDS; do curl -s -o /dev/null "$BASE_URL/api/produtos/$id/com-cache"; done
for id in $IDS; do medir produto-hit "/api/produtos/$id/com-cache"; done

echo "relatorio-sem";  for ((i = 1; i <= N_RELATORIO_BANCO; i++)); do medir relatorio-sem "$REL/sem-cache"; done
echo "relatorio-miss"; for ((i = 1; i <= N_RELATORIO_BANCO; i++)); do limpar; medir relatorio-miss "$REL/com-cache"; done
echo "relatorio-hit";  limpar; curl -s -o /dev/null "$BASE_URL$REL/com-cache"
for ((i = 1; i <= N_RELATORIO_HIT; i++)); do medir relatorio-hit "$REL/com-cache"; done

python3 -I "$RAIZ/analise/resumir_cache.py" "$CSV" | tee "$SAIDA/resumo.md"
