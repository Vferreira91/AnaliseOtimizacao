-- Q2: pedidos de um status num intervalo de datas.
-- Índice proposto: idx_pedido_status_data (status, data_pedido).
-- O uso do índice depende da seletividade: :status e o intervalo vêm do executar.sh.
--   seletivo: CANCELADO (~5% dos pedidos) em 30 dias  -> tende a usar o índice
--   amplo:    ENTREGUE  (~70% dos pedidos) em 2 anos  -> o planner prefere o Seq Scan
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, cliente_id, data_pedido, valor_total
FROM pedido
WHERE status = :'status'
  AND data_pedido BETWEEN :'inicio' AND :'fim'
ORDER BY data_pedido;
