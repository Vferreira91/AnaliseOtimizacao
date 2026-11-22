-- Volta ao cenário "sem índice": só as PKs do schema base.
-- Uso: docker exec -i ao-postgres psql -U app -d pedidos < db/indices/remover.sql

\set ON_ERROR_STOP on

DROP INDEX IF EXISTS idx_pedido_cliente_data;
DROP INDEX IF EXISTS idx_pedido_status_data;
DROP INDEX IF EXISTS idx_item_pedido_pedido;

ANALYZE pedido;
ANALYZE item_pedido;
