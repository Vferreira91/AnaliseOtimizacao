-- Q3a: itens de um pedido. É exatamente o SQL que o Hibernate dispara a cada carga LAZY de
-- PedidoLazy.itens (uma vez por pedido nos endpoints lazy e eager).
-- Índice proposto: idx_item_pedido_pedido (pedido_id), a FK que o Postgres não indexa sozinho.
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, quantidade, preco_unitario, produto_id
FROM item_pedido
WHERE pedido_id = 199990;
