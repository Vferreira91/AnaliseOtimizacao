#!/usr/bin/env bash
# Experimento obrigatório 3.4 do enunciado (cache: reaproveitamento, invalidação e expiração).
#
# Pré-requisito: API rodando com TTL curto:
#   cd app && SPRING_PROFILES_ACTIVE=demo ./mvnw spring-boot:run
# Uso: ./analise/experimento_cache.sh
#
# Parte A, produto (invalidação explícita):
#   consulta (MISS) -> repete (HIT) -> PUT altera o preço -> consulta (MISS, preço novo)
#   -> repete (HIT) -> espera o TTL -> chave some do Redis -> consulta (MISS)
# Parte B, relatório (só TTL, dado defasado):
#   consulta (MISS) -> cancela um pedido -> com cache continua com o número antigo (HIT),
#   sem cache já mostra o novo -> espera o TTL -> com cache passa a mostrar o novo (MISS)
#
# No final, o produto e o pedido voltam aos valores originais e o cache é esvaziado.
# Evidências: docs/evidencias/cache/experimento-3.4.md e redis-monitor.txt (comandos que a API
# enviou ao Redis durante o experimento, via redis-cli MONITOR).
set -euo pipefail
export LC_ALL=C

BASE_URL="${BASE_URL:-http://localhost:8080}"
PRODUTO="${PRODUTO:-42}"
PEDIDO="${PEDIDO:-200000}"
NOVO_PRECO="${NOVO_PRECO:-299.90}"
NOVO_ESTOQUE="${NOVO_ESTOQUE:-150}"

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
SAIDA="$RAIZ/docs/evidencias/cache"
mkdir -p "$SAIDA"
LOG="$SAIDA/experimento-3.4.md"
MONITOR="$SAIDA/redis-monitor.txt"
TMP="$(mktemp -d)"

# -F ' ': colunas separadas por espaço (o padrão do -A é '|'), para o `read` abaixo.
psql_q() { docker exec ao-postgres psql -U app -d pedidos -X -v ON_ERROR_STOP=1 -tA -F ' ' -c "$1"; }
redis() { docker exec ao-redis redis-cli "$@"; }
campo() { python3 -I -c "import json,sys; d=json.load(open(sys.argv[1])); print(eval(sys.argv[2], {}, {'d': d}))" "$TMP/corpo.json" "$1"; }
log() { echo "$*" | tee -a "$LOG"; }

# Requisição HTTP: guarda corpo e cabeçalhos e registra uma linha de tabela no log.
#   req <passo> <método> <caminho> [corpo-json] [expressão python sobre d para exibir]
req() {
    local passo="$1" metodo="$2" caminho="$3" corpo="${4:-}" expr="${5:-}"
    local args=(-s -X "$metodo" -D "$TMP/cab.txt" -o "$TMP/corpo.json")
    [[ -n "$corpo" ]] && args+=(-H 'Content-Type: application/json' -d "$corpo")
    curl "${args[@]}" "$BASE_URL$caminho"
    c() { grep -i "^$1:" "$TMP/cab.txt" | tr -d '\r' | awk '{print $2}'; }
    local mostra=""
    [[ -n "$expr" ]] && mostra="$(campo "$expr")"
    log "| $passo | \`$metodo $caminho\` | $(c X-Cache) | $(c X-SQL-Count) | $(c X-Elapsed-Ms) | $mostra |"
}

cabecalho_tabela() {
    log ""
    log "| Passo | Requisição | X-Cache | X-SQL-Count | X-Elapsed-Ms | Valor observado |"
    log "|---|---|---|---:|---:|---|"
}

curl -sf "$BASE_URL/actuator/health" > /dev/null || { echo "API fora do ar em $BASE_URL" >&2; exit 1; }

# Estado original, para restaurar no final.
ORIGINAL_PRODUTO="$(psql_q "SELECT preco, estoque, replace(atualizado_em::text, ' ', 'T') FROM produto WHERE id = $PRODUTO")"
read -r PRECO_ORIG ESTOQUE_ORIG ATUALIZADO_ORIG <<< "$ORIGINAL_PRODUTO"
STATUS_ORIG="$(psql_q "SELECT status FROM pedido WHERE id = $PEDIDO")"
[[ -n "$PRECO_ORIG" && -n "$ESTOQUE_ORIG" && -n "$ATUALIZADO_ORIG" && -n "$STATUS_ORIG" ]] \
    || { echo "Não foi possível ler o estado original do produto $PRODUTO / pedido $PEDIDO" >&2; exit 1; }

# Roda sempre ao sair, inclusive em erro. Sem `set -e` aqui: uma falha não pode impedir as
# etapas seguintes da limpeza. No fim confere se o banco voltou mesmo ao estado original.
restaurar() {
    set +e
    psql_q "UPDATE produto SET preco = $PRECO_ORIG, estoque = $ESTOQUE_ORIG, atualizado_em = '$ATUALIZADO_ORIG' WHERE id = $PRODUTO" > /dev/null
    psql_q "UPDATE pedido SET status = '$STATUS_ORIG' WHERE id = $PEDIDO" > /dev/null
    curl -s -X DELETE "$BASE_URL/api/admin/cache" > /dev/null
    # Encerra o MONITOR dentro do container; matar só o `docker exec` deixaria o redis-cli vivo.
    docker exec ao-redis pkill -f 'redis-cli MONITOR' 2> /dev/null
    [[ -n "${MONITOR_PID:-}" ]] && kill "$MONITOR_PID" 2> /dev/null
    rm -rf "$TMP"
    local agora
    agora="$(psql_q "SELECT preco, estoque, replace(atualizado_em::text, ' ', 'T') FROM produto WHERE id = $PRODUTO") $(psql_q "SELECT status FROM pedido WHERE id = $PEDIDO")"
    if [[ "$agora" == "$ORIGINAL_PRODUTO $STATUS_ORIG" ]]; then
        echo "Estado original restaurado (produto $PRODUTO e pedido $PEDIDO)."
    else
        echo "ATENÇÃO: restauração incompleta. Esperado '$ORIGINAL_PRODUTO $STATUS_ORIG', atual '$agora'." >&2
    fi
}
trap restaurar EXIT

curl -s -X DELETE "$BASE_URL/api/admin/cache" > /dev/null
docker exec ao-redis redis-cli MONITOR > "$MONITOR" 2> /dev/null &
MONITOR_PID=$!
sleep 1

: > "$LOG"
log "# Experimento 3.4: comportamento do cache"
log ""
log "Gerado por \`analise/experimento_cache.sh\` em $(date -Iseconds). Produto $PRODUTO, pedido $PEDIDO."
log "Valores medidos nesta execução; o cache foi esvaziado antes de começar."

# ---------------------------------------------------------------------------
log ""
log "## A. Produto: reaproveitamento, invalidação e expiração"
cabecalho_tabela
req "A1 consulta" GET "/api/produtos/$PRODUTO/com-cache" "" "d['preco']"
TTL_CONFIG="$(redis TTL "produtos::$PRODUTO")"
req "A2 repete" GET "/api/produtos/$PRODUTO/com-cache" "" "d['preco']"
req "A3 altera" PUT "/api/produtos/$PRODUTO" "{\"preco\": $NOVO_PRECO, \"estoque\": $NOVO_ESTOQUE}" "d['preco']"
EXISTE_APOS_PUT="$(redis EXISTS "produtos::$PRODUTO")"
req "A4 consulta" GET "/api/produtos/$PRODUTO/com-cache" "" "d['preco']"
req "A5 repete" GET "/api/produtos/$PRODUTO/com-cache" "" "d['preco']"

log ""
log "- TTL da chave \`produtos::$PRODUTO\` logo após o 1º MISS: **${TTL_CONFIG} s** (profile da API)."
log "- \`EXISTS produtos::$PRODUTO\` logo após o PUT: **$EXISTE_APOS_PUT** (0 = a entrada foi invalidada)."

log ""
log "Expiração (TTL lido no Redis enquanto o tempo passa):"
log ""
ttl_atual="$(redis TTL "produtos::$PRODUTO")"
log "- t = 0 s: TTL = $ttl_atual s"
sleep 5
log "- t = 5 s: TTL = $(redis TTL "produtos::$PRODUTO") s"
espera=$(( ttl_atual + 1 - 5 ))
(( espera > 0 )) && sleep "$espera"
log "- t = $(( ttl_atual + 1 )) s: TTL = $(redis TTL "produtos::$PRODUTO") (-2 = a chave não existe mais), EXISTS = $(redis EXISTS "produtos::$PRODUTO")"
cabecalho_tabela
req "A6 após expirar" GET "/api/produtos/$PRODUTO/com-cache" "" "d['preco']"

# ---------------------------------------------------------------------------
log ""
log "## B. Relatório: dado defasado até o TTL vencer"
log ""
log "O relatório não é invalidado por escritas. Cancelar o pedido $PEDIDO (status original: $STATUS_ORIG) muda o faturamento, mas a versão com cache continua servindo o valor antigo até expirar."
FAT="round(sum(c['faturamento'] for c in d['categorias']), 2)"
cabecalho_tabela
req "B1 consulta" GET "/api/relatorios/vendas-por-categoria/com-cache" "" "'geradoEm=' + d['geradoEm'] + ', faturamento total=' + str($FAT)"
req "B2 cancela pedido" PUT "/api/pedidos/$PEDIDO/status" '{"status": "CANCELADO"}' "d['status']"
req "B3 com cache" GET "/api/relatorios/vendas-por-categoria/com-cache" "" "'geradoEm=' + d['geradoEm'] + ', faturamento total=' + str($FAT)"
req "B4 sem cache" GET "/api/relatorios/vendas-por-categoria/sem-cache" "" "'geradoEm=' + d['geradoEm'] + ', faturamento total=' + str($FAT)"
ttl_rel="$(redis TTL relatorio-vendas::todas)"
log ""
log "Esperando ${ttl_rel} s para a entrada do relatório expirar..."
sleep $(( ttl_rel + 1 ))
cabecalho_tabela
req "B5 após expirar" GET "/api/relatorios/vendas-por-categoria/com-cache" "" "'geradoEm=' + d['geradoEm'] + ', faturamento total=' + str($FAT)"

log ""
log "Ao final, o produto, o pedido e o cache foram restaurados ao estado original."
sleep 1
echo
echo "Evidências em ${LOG#"$RAIZ"/} e ${MONITOR#"$RAIZ"/}"
