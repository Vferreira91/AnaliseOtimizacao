#!/usr/bin/env bash
# Executa a bateria de testes de carga: variantes × cargas (VUs) × repetições.
#
# Uso:
#   ./k6/rodar.sh                                   # rodada completa (protocolo do PLANO.md 6.2)
#   RODADA=teste CARGAS="10 50" REPETICOES=1 AQUECIMENTO=5s COLETA=10s ./k6/rodar.sh
#
# Variáveis (com o padrão):
#   RODADA       nome da pasta em k6/resultados/   (data e hora)
#   VARIANTES    lista de variantes                 (todas de C1, C2 e C3)
#   CARGAS       VUs simultâneos                    (10 50 100 200)
#   REPETICOES   repetições de cada combinação      (3)
#   AQUECIMENTO / COLETA  durações do k6            (30s / 60s)
#   N_PEDIDOS    n dos endpoints de C2              (50)
#
# Antes de CADA execução o runner:
#   1. ajusta os índices (só as variantes C3 "sem-indice" rodam sem eles);
#   2. reinicia o container da API (JVM fria; o aquecimento do k6 a esquenta);
#   3. esvazia o cache e, na variante "quente", pré-carrega os 100 produtos usados;
#   4. amostra `docker stats` (CPU/memória de app, postgres, redis) durante o teste.
# Cada repetição percorre todas as variantes e cargas, para que uma deriva no tempo
# (aquecimento da máquina, outras tarefas) se espalhe entre as variantes.
#
# Pré-requisitos: docker compose --profile carga up -d app; banco populado.
# Resultado: k6/resultados/<RODADA>/*.json e *.stats.csv. Gráficos: analise/gerar_graficos.py
set -euo pipefail
export LC_ALL=C

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"

RODADA="${RODADA:-$(date +%Y%m%d-%H%M)}"
VARIANTES="${VARIANTES:-produto-sem produto-com-frio produto-com-quente relatorio-sem relatorio-com pedidos-lazy pedidos-eager pedidos-join-fetch pedidos-dto cliente-pedidos-sem-indice cliente-pedidos-com-indice}"
CARGAS="${CARGAS:-10 50 100 200}"
REPETICOES="${REPETICOES:-3}"
AQUECIMENTO="${AQUECIMENTO:-30s}"
COLETA="${COLETA:-60s}"
N_PEDIDOS="${N_PEDIDOS:-50}"
BASE_URL="${BASE_URL:-http://localhost:8080}"

DIR="$RAIZ/k6/resultados/$RODADA"
mkdir -p "$DIR"

psql_arquivo() { docker exec -i ao-postgres psql -U app -d pedidos -X -q -v ON_ERROR_STOP=1 < "$1" > /dev/null; }

estado_indices=""
ajustar_indices() {
    local desejado="com"
    [[ "$1" == *-sem-indice ]] && desejado="sem"
    [[ "$desejado" == "$estado_indices" ]] && return
    if [[ "$desejado" == "sem" ]]; then psql_arquivo db/indices/remover.sql; else psql_arquivo db/indices/criar.sql; fi
    estado_indices="$desejado"
}

esperar_api() {
    for _ in $(seq 1 60); do
        curl -sf "$BASE_URL/actuator/health" > /dev/null && return
        sleep 1
    done
    echo "A API não respondeu em 60 s" >&2
    exit 1
}

preparar_cache() {
    local produto  # local: não pode sobrescrever o `id` da execução no laço principal
    curl -sf -X DELETE "$BASE_URL/api/admin/cache" > /dev/null
    if [[ "$1" == produto-com-quente ]]; then
        for produto in $(seq 1 100); do curl -sf -o /dev/null "$BASE_URL/api/produtos/$produto/com-cache"; done
    fi
}

# Amostra CPU e memória dos containers até receber SIGTERM.
amostrar_stats() {
    local arquivo="$1"
    echo "epoch,container,cpu_pct,mem_mib" > "$arquivo"
    while true; do
        docker stats --no-stream --format '{{.Name}},{{.CPUPerc}},{{.MemUsage}}' ao-app ao-postgres ao-redis 2> /dev/null \
            | awk -F, -v t="$(date +%s.%N)" '{
                gsub("%", "", $2); split($3, m, " / "); v = m[1];
                if (v ~ /GiB/) { sub("GiB", "", v); v *= 1024 } else if (v ~ /MiB/) { sub("MiB", "", v) } else if (v ~ /KiB/) { sub("KiB", "", v); v /= 1024 }
                printf "%s,%s,%s,%.1f\n", t, $1, $2, v }' >> "$arquivo" || true
    done
}

{
    echo "rodada=$RODADA"
    echo "inicio=$(date -Iseconds)"
    echo "variantes=$VARIANTES"
    echo "cargas=$CARGAS repeticoes=$REPETICOES aquecimento=$AQUECIMENTO coleta=$COLETA n_pedidos=$N_PEDIDOS"
    echo "db_pool_size=$(docker exec ao-app printenv DB_POOL_SIZE 2> /dev/null || echo '?')"
    echo "host=$(nproc) CPUs, $(free -g | awk '/Mem:/ {print $2}') GiB RAM, $(uname -r)"
    docker exec ao-postgres psql -U app -d pedidos -X -tAc \
        "SELECT 'linhas: pedido=' || (SELECT count(*) FROM pedido) || ' item_pedido=' || (SELECT count(*) FROM item_pedido) || ' produto=' || (SELECT count(*) FROM produto) || ' cliente=' || (SELECT count(*) FROM cliente)"
} > "$DIR/rodada.txt"

total=$(( $(wc -w <<< "$VARIANTES") * $(wc -w <<< "$CARGAS") * REPETICOES ))
i=0
for ((r = 1; r <= REPETICOES; r++)); do
    for variante in $VARIANTES; do
        for vus in $CARGAS; do
            i=$((i + 1))
            id="${variante}_${vus}vus_r${r}"
            echo "[$i/$total] $id"
            ajustar_indices "$variante"
            docker restart ao-app > /dev/null
            esperar_api
            preparar_cache "$variante"

            amostrar_stats "$DIR/$id.stats.csv" &
            pid_stats=$!
            echo "inicio_epoch=$(date +%s.%N)" > "$DIR/$id.tempo"
            k6 run -q --no-color \
                -e BASE_URL="$BASE_URL" -e VARIANTE="$variante" -e VUS="$vus" -e REPETICAO="$r" \
                -e AQUECIMENTO="$AQUECIMENTO" -e COLETA="$COLETA" -e N_PEDIDOS="$N_PEDIDOS" \
                -e SAIDA="$DIR/$id.json" k6/carga.js 2>> "$DIR/k6-erros.log" | sed 's/^/    /'
            kill "$pid_stats" 2> /dev/null; wait "$pid_stats" 2> /dev/null || true
        done
    done
done

# Deixa o banco como o resto do projeto espera: com os índices de experimento.
ajustar_indices "fim"
echo "fim=$(date -Iseconds)" >> "$DIR/rodada.txt"
echo "Resultados em ${DIR#"$RAIZ"/}"
