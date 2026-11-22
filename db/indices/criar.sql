-- Índices dos experimentos (Item 2, seção 5 do enunciado).
-- O schema base (V1) só tem as PKs; estes índices são criados e removidos sob demanda
-- para comparar o "antes" e o "depois" com EXPLAIN ANALYZE e com os endpoints.
-- Uso: docker exec -i ao-postgres psql -U app -d pedidos < db/indices/criar.sql

\set ON_ERROR_STOP on
\timing on

-- Q1: pedidos de um cliente, do mais recente ao mais antigo.
-- Coluna de igualdade primeiro, depois a de ordenação: o Postgres lê o índice já na ordem
-- pedida e dispensa o Sort.
CREATE INDEX IF NOT EXISTS idx_pedido_cliente_data ON pedido (cliente_id, data_pedido DESC);

-- Q2: pedidos de um status num intervalo de datas.
CREATE INDEX IF NOT EXISTS idx_pedido_status_data ON pedido (status, data_pedido);

-- Q3: FK item_pedido.pedido_id. O Postgres não indexa FKs automaticamente; sem este índice,
-- cada carga LAZY dos itens de um pedido é um Seq Scan em ~1,1 milhão de linhas.
CREATE INDEX IF NOT EXISTS idx_item_pedido_pedido ON item_pedido (pedido_id);

ANALYZE pedido;
ANALYZE item_pedido;
