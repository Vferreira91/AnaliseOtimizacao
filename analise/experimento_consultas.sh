#!/usr/bin/env bash
# Roteiro completo do Item 2, do cenário "sem índice" ao "com índice", na ordem:
#   1. remove os índices de experimento (só PKs)
#   2. EXPLAIN ANALYZE das consultas Q1–Q3            -> docs/evidencias/explain/sem-indice/
#   3. mede os endpoints /api/pedidos/*               -> docs/evidencias/consultas/sem-indice.csv
#   4. custo de escrita sem índices                   -> docs/evidencias/indices/custo-sem-indice.txt
#   5. cria os índices (tempo de criação)             -> docs/evidencias/indices/criacao.txt
#   6. custo de escrita com índices                   -> docs/evidencias/indices/custo-com-indice.txt
#   7. EXPLAIN ANALYZE de novo                        -> docs/evidencias/explain/com-indice/
#   8. mede os endpoints de novo                      -> docs/evidencias/consultas/com-indice.csv
#   9. resume as medições                             -> docs/evidencias/consultas/resumo.md
#
# Pré-requisitos: docker compose up -d, banco populado (db/seed/popular.sh) e a API rodando.
# Os índices ficam criados no final (rode db/indices/remover.sql para voltar ao início).
# Não rode nada pesado em paralelo: as medições são sensíveis a ruído.
set -euo pipefail

RAIZ="$(cd "$(dirname "$0")/.." && pwd)"
cd "$RAIZ"
CONTAINER="${CONTAINER:-ao-postgres}"
psql_arquivo() { docker exec -i "$CONTAINER" psql -U app -d pedidos -X -v ON_ERROR_STOP=1 < "$1"; }

mkdir -p docs/evidencias/indices

echo "== 1. Removendo índices de experimento"
psql_arquivo db/indices/remover.sql > /dev/null

echo "== 2. EXPLAIN sem índice"
./db/explain/executar.sh sem-indice

echo "== 3. Endpoints sem índice"
./analise/medir_consultas.sh sem-indice

echo "== 4. Custo de escrita sem índices"
psql_arquivo db/indices/custo.sql > docs/evidencias/indices/custo-sem-indice.txt

echo "== 5. Criando índices"
psql_arquivo db/indices/criar.sql > docs/evidencias/indices/criacao.txt

echo "== 6. Custo de escrita com índices"
psql_arquivo db/indices/custo.sql > docs/evidencias/indices/custo-com-indice.txt

echo "== 7. EXPLAIN com índice"
./db/explain/executar.sh com-indice

echo "== 8. Endpoints com índice"
./analise/medir_consultas.sh com-indice

echo "== 9. Resumo"
python3 analise/resumir_consultas.py > /dev/null
echo "Concluído. Resumo em docs/evidencias/consultas/resumo.md"
