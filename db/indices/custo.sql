-- Custo de manter índices: tamanho em disco e tempo de escrita.
-- Rode duas vezes, uma sem e outra com os índices (db/indices/remover.sql / criar.sql),
-- e compare os tempos. Os INSERTs são desfeitos com ROLLBACK, então o banco não muda.
-- Uso: docker exec -i ao-postgres psql -U app -d pedidos < db/indices/custo.sql

\set ON_ERROR_STOP on
\pset footer off

\echo '== Índices existentes e tamanho =='
SELECT c.relname AS tabela, i.relname AS indice, pg_size_pretty(pg_relation_size(i.oid)) AS tamanho
FROM pg_index x
JOIN pg_class i ON i.oid = x.indexrelid
JOIN pg_class c ON c.oid = x.indrelid
WHERE c.relname IN ('pedido', 'item_pedido')
ORDER BY c.relname, i.relname;

\echo '== Tamanho total (tabela + índices) =='
SELECT relname AS tabela,
       pg_size_pretty(pg_relation_size(oid)) AS tabela_tam,
       pg_size_pretty(pg_indexes_size(oid))  AS indices_tam
FROM pg_class WHERE relname IN ('pedido', 'item_pedido') ORDER BY relname;

\echo '== Escrita: 50.000 pedidos + 250.000 itens (desfeito com ROLLBACK) =='
\timing on
BEGIN;
INSERT INTO pedido (cliente_id, data_pedido, status, valor_total)
SELECT 1 + (g % 10000), timestamp '2026-11-01' + g * interval '1 second', 'PENDENTE', 0
FROM generate_series(1, 50000) AS g;

INSERT INTO item_pedido (pedido_id, produto_id, quantidade, preco_unitario)
SELECT 1 + (g % 200000), 1 + (g % 20000), 1, 10
FROM generate_series(1, 250000) AS g;

UPDATE pedido SET status = 'PAGO' WHERE id BETWEEN 1 AND 20000;
ROLLBACK;
\timing off

-- As linhas desfeitas viram tuplas mortas no fim das tabelas. O VACUUM as remove e devolve as
-- páginas finais ao sistema, para não inflar os Seq Scans dos experimentos seguintes.
-- Os índices (inclusive as PKs) também recebem as entradas desfeitas e não encolhem com o
-- VACUUM; o REINDEX os reconstrói compactos.
VACUUM pedido;
VACUUM item_pedido;
REINDEX TABLE pedido;
REINDEX TABLE item_pedido;
