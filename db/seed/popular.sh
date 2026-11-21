#!/usr/bin/env bash
# Popula o banco do container ao-postgres e mostra a conferência dos volumes.
#
# Pré-requisitos: `docker compose up -d` e a aplicação já iniciada uma vez
# (o Flyway cria o schema na inicialização).
#
# Volumes ajustáveis por variável de ambiente, por exemplo:
#   N_PEDIDOS=50000 ./db/seed/popular.sh
set -euo pipefail

cd "$(dirname "$0")"

CONTAINER="${CONTAINER:-ao-postgres}"
PSQL=(docker exec -i "$CONTAINER" psql -U app -d pedidos -X -q)

if ! "${PSQL[@]}" -tAc "SELECT to_regclass('public.item_pedido')" | grep -q item_pedido; then
    echo "Schema não encontrado. Suba a aplicação uma vez para o Flyway criar as tabelas." >&2
    exit 1
fi

"${PSQL[@]}" \
    -v n_categorias="${N_CATEGORIAS:-50}" \
    -v n_produtos="${N_PRODUTOS:-20000}" \
    -v n_clientes="${N_CLIENTES:-10000}" \
    -v n_pedidos="${N_PEDIDOS:-200000}" \
    -v max_itens="${MAX_ITENS:-10}" \
    < seed.sql

echo
"${PSQL[@]}" < conferir.sql
