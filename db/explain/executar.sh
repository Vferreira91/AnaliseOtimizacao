#!/usr/bin/env bash
# Roda as consultas de db/explain com EXPLAIN (ANALYZE, BUFFERS) e salva as evidências.
#
# Uso: ./db/explain/executar.sh <rotulo>      (ex.: sem-indice, com-indice)
#
# Para cada caso, executa a consulta REPETICOES vezes (a primeira aquece o cache do Postgres),
# guarda o plano completo da última execução em docs/evidencias/explain/<rotulo>/<caso>.txt
# e registra em resumo.tsv os tempos de execução de todas as execuções medidas e a mediana.
set -euo pipefail
export LC_ALL=C   # ponto decimal no awk/sort, independente do idioma do sistema

ROTULO="${1:?informe um rótulo, ex.: sem-indice ou com-indice}"
REPETICOES="${REPETICOES:-6}"
CONTAINER="${CONTAINER:-ao-postgres}"

RAIZ="$(cd "$(dirname "$0")/../.." && pwd)"
DIR_SQL="$RAIZ/db/explain"
SAIDA="$RAIZ/docs/evidencias/explain/$ROTULO"
mkdir -p "$SAIDA"

PSQL=(docker exec -i "$CONTAINER" psql -U app -d pedidos -X -q -v ON_ERROR_STOP=1)

# caso | arquivo | variáveis do psql
CASOS=(
    "q1_cliente_tipico|q1_pedidos_do_cliente.sql|-v cliente=5000"
    "q1_cliente_pesado|q1_pedidos_do_cliente.sql|-v cliente=1"
    "q2_seletivo|q2_status_periodo.sql|-v status=CANCELADO -v inicio=2026-09-01 -v fim=2026-10-01"
    "q2_amplo|q2_status_periodo.sql|-v status=ENTREGUE -v inicio=2024-11-01 -v fim=2026-11-01"
    "q3a_itens_do_pedido|q3_itens_do_pedido.sql|"
    "q3b_join_recentes|q3b_join_recentes.sql|"
)

{
    echo "# rotulo=$ROTULO data=$(date -Iseconds) repeticoes=$REPETICOES (a 1ª é aquecimento)"
    "${PSQL[@]}" -tAc "SELECT 'indices: ' || coalesce(string_agg(indexname, ', ' ORDER BY indexname), '(nenhum)') FROM pg_indexes WHERE schemaname='public' AND indexname LIKE 'idx_%'"
    printf "caso\tmediana_ms\texecucoes_ms\n"
} > "$SAIDA/resumo.tsv"

for caso in "${CASOS[@]}"; do
    IFS='|' read -r nome arquivo vars <<< "$caso"
    tempos=()
    for ((r = 1; r <= REPETICOES; r++)); do
        # shellcheck disable=SC2086
        plano=$("${PSQL[@]}" $vars < "$DIR_SQL/$arquivo")
        t=$(grep -oP 'Execution Time: \K[0-9.]+' <<< "$plano")
        if ((r > 1)); then tempos+=("$t"); fi
    done
    printf '%s\n' "$plano" > "$SAIDA/$nome.txt"
    mediana=$(printf '%s\n' "${tempos[@]}" | sort -g | awk '{a[NR]=$1} END {print (NR%2 ? a[(NR+1)/2] : (a[NR/2]+a[NR/2+1])/2)}')
    printf "%s\t%s\t%s\n" "$nome" "$mediana" "${tempos[*]}" >> "$SAIDA/resumo.tsv"
    echo "$nome: mediana ${mediana} ms"
done

echo "Evidências em ${SAIDA#"$RAIZ"/}"
