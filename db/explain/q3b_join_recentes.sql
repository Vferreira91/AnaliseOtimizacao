-- Q3b: os 100 pedidos mais recentes com itens, produto e cliente: o mesmo formato do SQL do
-- endpoint /api/pedidos/nativo (e, na prática, do JOIN FETCH). Mostra o efeito do índice
-- idx_item_pedido_pedido num JOIN: sem ele, Hash Join com Seq Scan em item_pedido; com ele,
-- Nested Loop com Index Scan.
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.id, p.data_pedido, p.status, p.valor_total,
       c.id, c.nome, c.cidade, c.uf,
       i.id, i.quantidade, i.preco_unitario,
       pr.id, pr.nome
FROM (SELECT id, cliente_id, data_pedido, status, valor_total
      FROM pedido
      ORDER BY id DESC
      LIMIT 100) p
JOIN cliente c      ON c.id = p.cliente_id
JOIN item_pedido i  ON i.pedido_id = p.id
JOIN produto pr     ON pr.id = i.produto_id
ORDER BY p.id DESC, i.id;
