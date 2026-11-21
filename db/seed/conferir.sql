-- Conferência dos volumes e das distribuições geradas pelo seed.
-- Uso: docker exec -i ao-postgres psql -U app -d pedidos < db/seed/conferir.sql

\pset footer off

\echo '== Linhas por tabela =='
SELECT 'categoria' AS tabela, count(*) AS linhas FROM categoria
UNION ALL SELECT 'produto', count(*) FROM produto
UNION ALL SELECT 'cliente', count(*) FROM cliente
UNION ALL SELECT 'pedido', count(*) FROM pedido
UNION ALL SELECT 'item_pedido', count(*) FROM item_pedido;

\echo '== Tamanho em disco (tabela + índices) =='
SELECT relname AS tabela,
       pg_size_pretty(pg_relation_size(oid))       AS tabela_tam,
       pg_size_pretty(pg_indexes_size(oid))        AS indices_tam,
       pg_size_pretty(pg_total_relation_size(oid)) AS total
FROM pg_class
WHERE relname IN ('categoria', 'produto', 'cliente', 'pedido', 'item_pedido')
ORDER BY pg_total_relation_size(oid) DESC;

\echo '== Índices existentes (devem ser só as PKs) =='
SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'public' AND tablename <> 'flyway_schema_history'
ORDER BY tablename, indexname;

\echo '== Status dos pedidos =='
SELECT status, count(*) AS pedidos,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM pedido
GROUP BY status
ORDER BY pedidos DESC;

\echo '== Pedidos por cliente (cauda longa) =='
SELECT min(n) AS minimo,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY n) AS mediana,
       round(avg(n), 1) AS media,
       max(n) AS maximo,
       (SELECT count(*) FROM cliente c
         WHERE NOT EXISTS (SELECT 1 FROM pedido p WHERE p.cliente_id = c.id)) AS clientes_sem_pedido
FROM (SELECT cliente_id, count(*) AS n FROM pedido GROUP BY cliente_id) AS x;

\echo '== Clientes com mais pedidos =='
SELECT cliente_id, count(*) AS pedidos
FROM pedido
GROUP BY cliente_id
ORDER BY pedidos DESC
LIMIT 5;

\echo '== Itens por pedido =='
SELECT min(n) AS minimo, round(avg(n), 2) AS media, max(n) AS maximo
FROM (SELECT pedido_id, count(*) AS n FROM item_pedido GROUP BY pedido_id) AS x;

\echo '== Intervalo de datas dos pedidos =='
SELECT min(data_pedido) AS primeiro, max(data_pedido) AS ultimo FROM pedido;

\echo '== Consistência: valor_total = soma dos itens =='
SELECT count(*) AS pedidos_inconsistentes
FROM pedido p
JOIN (SELECT pedido_id, sum(quantidade * preco_unitario) AS total
      FROM item_pedido GROUP BY pedido_id) t ON t.pedido_id = p.id
WHERE p.valor_total <> t.total;
