#!/usr/bin/env bash
# Demonstração ao vivo para o vídeo e a apresentação (item 7.3). Roteiro: docs/roteiro-video.md
#
# Uso:  ./analise/demo.sh <bloco>
#   aquecer      antes de gravar: aquece a JVM (~1 min) e esvazia o cache
#   ambiente     containers, limites e volume de dados
#   api          uma requisição e os cabeçalhos de instrumentação
#   cache        MISS → HIT → PUT invalida → MISS com valor novo; TTL no Redis; relatório
#   consultas    SQL por estratégia (mesmo JSON) e o N+1 chegando ao Postgres
#   indices      EXPLAIN ANALYZE da Q1 sem e com índice
#   carga        k6: LAZY × DTO com 50 VUs (5 s de aquecimento + 15 s de coleta cada)
#   restaurar    deixa tudo como antes: produto 42, cache vazio, índices, log do Postgres, API no profile padrão
#
# Pré-requisitos: docker compose up -d; banco populado; API em container com TTL curto:
#   SPRING_PROFILES_ACTIVE=demo docker compose --profile carga up -d app
# Entre um passo e outro o script espera Enter (DEMO_SEM_PAUSA=1 desliga as pausas).
set -euo pipefail
export LC_ALL=C

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
API="${BASE_URL:-http://localhost:8080}"
CORPO="$(mktemp)"
trap 'rm -f "$CORPO"' EXIT

negrito=$'\e[1m'; ciano=$'\e[36m'; amarelo=$'\e[33m'; normal=$'\e[0m'

titulo() { printf '\n%s== %s ==%s\n' "$negrito" "$1" "$normal"; }
pausa()  { [[ "${DEMO_SEM_PAUSA:-}" == 1 ]] && return; read -rsp "${amarelo}[Enter]${normal}" < /dev/tty; echo; }
mostra() { printf '%s$ %s%s\n' "$ciano" "$*" "$normal"; }
# Mostra o comando e o executa.
roda()   { mostra "$*"; eval "$@"; }

psql_c() { docker exec ao-postgres psql -U app -d pedidos -X -q "$@"; }

# Requisição HTTP mostrando o status, os cabeçalhos X-* e um resumo do corpo (filtro jq opcional).
req() {
    local metodo="$1" caminho="$2" filtro="${3:-.}" dados="${4:-}"
    local extra=()
    [[ -n "$dados" ]] && extra=(-H 'Content-Type: application/json' -d "$dados")
    mostra "curl -X $metodo $caminho${dados:+ -d '$dados'}"
    curl -s -X "$metodo" "${extra[@]}" -D - -o "$CORPO" "$API$caminho" \
        | tr -d '\r' | grep -E '^(HTTP|X-)' | sed 's/^/    /'
    [[ -s "$CORPO" ]] && jq -c "$filtro" "$CORPO" | cut -c1-160 | sed 's/^/    /'
    return 0
}

# Só os cabeçalhos de uma requisição, numa linha: "SQL=.. tempo=.. cache=.. md5=.."
cabecalhos() {
    curl -s -D - -o "$CORPO" "$API$1" | tr -d '\r' | awk -F': ' '
        /^X-SQL-Count/ {s=$2} /^X-Elapsed-Ms/ {t=$2} /^X-Cache/ {c=$2}
        END {printf "SQL=%-5s tempo=%8s ms%s", s, t, (c ? "  cache=" c : "")}'
    printf '  md5(JSON)=%s\n' "$(md5sum < "$CORPO" | cut -c1-12)"
}

bloco_ambiente() {
    titulo "Containers (Postgres, Redis e a API com limites fixos de CPU e memória)"
    roda "docker compose --profile carga ps --format 'table {{.Name}}\t{{.Image}}\t{{.Status}}'"
    roda "docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}' ao-app ao-postgres ao-redis"
    pausa
    titulo "Volume de dados"
    roda "psql_c -c \"SELECT (SELECT count(*) FROM categoria) categorias, (SELECT count(*) FROM produto) produtos,
          (SELECT count(*) FROM cliente) clientes, (SELECT count(*) FROM pedido) pedidos, (SELECT count(*) FROM item_pedido) itens\""
}

bloco_api() {
    titulo "Uma requisição: o corpo e os cabeçalhos de instrumentação"
    req GET /api/produtos/42/sem-cache
    pausa
    req GET /api/clientes/5000/pedidos '{pedidos: length, mais_recente: .[0]}'
}

bloco_cache() {
    local original
    original="$(psql_c -tA -F ' ' -c "SELECT preco, estoque, atualizado_em FROM produto WHERE id = 42")"
    curl -s -o /dev/null -X DELETE "$API/api/admin/cache"

    titulo "1. Primeira consulta: MISS, vai ao banco (1 SQL) e grava no Redis"
    req GET /api/produtos/42/com-cache '{id, preco, estoque}'
    pausa
    titulo "2. Repete: HIT, nenhum SQL"
    req GET /api/produtos/42/com-cache '{id, preco, estoque}'
    pausa
    titulo "3. A entrada no Redis e o TTL (profile demo: 20 s)"
    roda "docker exec ao-redis redis-cli TTL produtos::42"
    sleep 3
    roda "docker exec ao-redis redis-cli TTL produtos::42"
    roda "docker exec ao-redis redis-cli GET produtos::42"
    pausa
    titulo "4. Altera o produto pela API: o PUT invalida a entrada"
    req PUT /api/produtos/42 '{id, preco, estoque}' '{"preco": 299.90, "estoque": 150}'
    roda "docker exec ao-redis redis-cli EXISTS produtos::42"
    pausa
    titulo "5. Consulta de novo: MISS e já com o preço novo"
    req GET /api/produtos/42/com-cache '{id, preco, estoque}'
    pausa
    titulo "6. Onde o cache rende: o relatório (agrega ~1,1 milhão de itens)"
    req GET /api/relatorios/vendas-por-categoria/com-cache '{geradoEm, categorias: (.categorias | length)}'
    req GET /api/relatorios/vendas-por-categoria/com-cache '{geradoEm, categorias: (.categorias | length)}'

    # Devolve o produto 42 ao estado original (preço, estoque e data) e esvazia o cache.
    read -r preco estoque data hora <<< "$original"
    psql_c -c "UPDATE produto SET preco = $preco, estoque = $estoque, atualizado_em = '$data $hora' WHERE id = 42"
    curl -s -o /dev/null -X DELETE "$API/api/admin/cache"
    printf '\n(produto 42 restaurado: %s)\n' "$original"
}

# Faz a requisição e lista, numerados, os comandos SQL que chegaram ao Postgres por causa dela
# (exige log_statement = 'all'). Lê só as linhas novas do log do container.
sql_no_postgres() {
    local caminho="$1" largura="$2" antes
    antes=$(docker logs ao-postgres 2>&1 | wc -l)
    mostra "curl '$caminho'   # e depois: docker logs ao-postgres (só as linhas novas)"
    curl -s -o /dev/null "$API$caminho"
    sleep 1
    docker logs ao-postgres 2>&1 | tail -n +$((antes + 1)) \
        | grep -oE 'execute [^:]*: .*' | sed -E 's/^execute [^:]*: //' \
        | grep -vE '^(BEGIN|COMMIT|ROLLBACK)' | cut -c1-"$largura" | cat -n
}

bloco_consultas() {
    titulo "Os 10 pedidos mais recentes com cliente, itens e produto: SQL por estratégia"
    mostra 'for e in lazy eager join-fetch entity-graph batch dto nativo; do curl "/api/pedidos/$e?n=10"; done'
    for e in lazy eager join-fetch entity-graph batch dto nativo; do
        printf '    %-13s ' "$e"; cabecalhos "/api/pedidos/$e?n=10"
    done
    echo "    (mesmo md5 = o JSON é idêntico em todas as estratégias)"
    pausa
    titulo "O N+1 visto pelo Postgres: LAZY com n = 2"
    roda "psql_c -c \"ALTER SYSTEM SET log_statement = 'all'\" -c 'SELECT pg_reload_conf()' > /dev/null"
    sleep 1
    sql_no_postgres "/api/pedidos/lazy?n=2" 110
    pausa
    titulo "O mesmo com JOIN FETCH: uma consulta só"
    sql_no_postgres "/api/pedidos/join-fetch?n=2" 400
    psql_c -c "ALTER SYSTEM RESET log_statement" -c 'SELECT pg_reload_conf()' > /dev/null
}

Q1="EXPLAIN (ANALYZE, COSTS OFF) SELECT * FROM pedido WHERE cliente_id = 5000 ORDER BY data_pedido DESC"

bloco_indices() {
    titulo "Q1 sem índice: pedidos do cliente 5000"
    roda "psql_c -c 'DROP INDEX IF EXISTS idx_pedido_cliente_data'"
    roda "psql_c -c '$Q1'"
    printf '    '; cabecalhos /api/clientes/5000/pedidos
    pausa
    titulo "Cria o índice (cliente_id, data_pedido DESC) e repete"
    roda "psql_c -c 'CREATE INDEX idx_pedido_cliente_data ON pedido (cliente_id, data_pedido DESC)' -c 'ANALYZE pedido'"
    roda "psql_c -c '$Q1'"
    printf '    '; cabecalhos /api/clientes/5000/pedidos
}

bloco_carga() {
    mkdir -p k6/resultados/demo
    for variante in pedidos-lazy pedidos-dto; do
        titulo "k6: $variante, 50 usuários virtuais simultâneos"
        roda "k6 run -q -e VARIANTE=$variante -e VUS=50 -e AQUECIMENTO=5s -e COLETA=15s -e SAIDA=k6/resultados/demo/$variante.json k6/carga.js"
        pausa
    done
}

# Antes de gravar: exercita cada caminho de código para o JIT compilar (a JVM recém-iniciada é
# mais lenta, e um HIT pode sair mais lento que um MISS). ~1 min. Termina com o cache vazio.
bloco_aquecer() {
    titulo "Aquecendo a JVM (10 VUs, 8 s por variante)"
    for variante in produto-sem produto-com-quente relatorio-com pedidos-lazy pedidos-eager \
                    pedidos-join-fetch pedidos-dto cliente-pedidos-com-indice; do
        printf '    %s\n' "$variante"
        k6 run -q -e VARIANTE="$variante" -e VUS=10 -e AQUECIMENTO=8s -e COLETA=1s \
            -e SAIDA=/dev/null k6/carga.js > /dev/null 2>&1 || true
    done
    for e in entity-graph batch nativo; do
        for _ in $(seq 1 50); do curl -s -o /dev/null "$API/api/pedidos/$e?n=10"; done
    done
    curl -s -o /dev/null -X DELETE "$API/api/admin/cache"
    echo "Pronto: JVM aquecida e cache vazio."
}

bloco_restaurar() {
    titulo "Restaurando o ambiente"
    # Produto 42 com os valores do seed (o Postman altera o produto pelo PUT, e o PUT muda a data).
    psql_c -c "UPDATE produto SET preco = 244.88, estoque = 200, atualizado_em = '2026-05-27 19:09:03.445819' WHERE id = 42"
    curl -s -o /dev/null -X DELETE "$API/api/admin/cache"
    psql_c -c "ALTER SYSTEM RESET log_statement" -c 'SELECT pg_reload_conf()' > /dev/null
    docker exec -i ao-postgres psql -U app -d pedidos -X -q < db/indices/criar.sql > /dev/null 2>&1
    psql_c -tAc "SELECT string_agg(indexname, ', ' ORDER BY indexname) FROM pg_indexes WHERE indexname LIKE 'idx_%'"
    SPRING_PROFILES_ACTIVE= docker compose --profile carga up -d app
    echo "Produto 42 como no seed, cache vazio, log do Postgres desligado, índices criados, API no profile padrão."
}

case "${1:-}" in
    aquecer|ambiente|api|cache|consultas|indices|carga|restaurar) "bloco_$1" ;;
    *) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
