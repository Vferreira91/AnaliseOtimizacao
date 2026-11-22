-- Q1: pedidos de um cliente, do mais recente ao mais antigo (endpoint GET /api/clientes/{id}/pedidos).
-- Índice proposto: idx_pedido_cliente_data (cliente_id, data_pedido DESC).
-- Sem índice: Seq Scan em pedido + Sort. Com índice: Index Scan já ordenado, sem Sort.
-- :cliente vem do script executar.sh (padrão 5000, um cliente "típico").
EXPLAIN (ANALYZE, BUFFERS)
SELECT *
FROM pedido
WHERE cliente_id = :cliente
ORDER BY data_pedido DESC;
