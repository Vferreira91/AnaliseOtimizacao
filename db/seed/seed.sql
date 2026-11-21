-- Popula o banco com dados sintéticos via generate_series.
--
-- Pré-requisito: schema criado pelo Flyway (basta subir a aplicação uma vez).
-- Uso normal: ./db/seed/popular.sh (aceita os volumes por variável de ambiente).
--
-- Volumes (variáveis do psql, com os valores padrão do PLANO.md):
--   n_categorias = 50, n_produtos = 20000, n_clientes = 10000,
--   n_pedidos = 200000, max_itens = 10 (cada pedido tem de 1 a max_itens itens)
--
-- As distribuições são propositalmente NÃO uniformes, para exercitar filtros e o planner:
--   * produto por categoria: concentrado nas categorias de id baixo;
--   * pedido por cliente: cauda longa (o cliente 1 tem ~1% dos pedidos, os últimos têm poucos);
--   * status: 70% ENTREGUE, 10% ENVIADO, 8% PAGO, 7% PENDENTE, 5% CANCELADO;
--   * data_pedido: espalhada nos ~3 anos anteriores a 2026-11-01;
--   * item por produto: produtos de id baixo são mais vendidos.
--
-- O setseed() torna a geração reprodutível: os mesmos parâmetros geram os mesmos dados.

\set ON_ERROR_STOP on

\if :{?n_categorias} \else \set n_categorias 50     \endif
\if :{?n_produtos}   \else \set n_produtos   20000  \endif
\if :{?n_clientes}   \else \set n_clientes   10000  \endif
\if :{?n_pedidos}    \else \set n_pedidos    200000 \endif
\if :{?max_itens}    \else \set max_itens    10     \endif

\echo 'Volumes: categorias=' :n_categorias ' produtos=' :n_produtos ' clientes=' :n_clientes ' pedidos=' :n_pedidos ' max_itens=' :max_itens
\timing on

BEGIN;

TRUNCATE item_pedido, pedido, produto, cliente, categoria RESTART IDENTITY;

SELECT setseed(0.42);

-- Categorias -----------------------------------------------------------------
INSERT INTO categoria (nome, descricao)
SELECT 'Categoria ' || g,
       'Descrição da categoria ' || g
FROM generate_series(1, :n_categorias) AS g;

-- Produtos -------------------------------------------------------------------
-- power(random(), 2) concentra os produtos nas categorias de id baixo.
INSERT INTO produto (nome, preco, estoque, categoria_id, atualizado_em)
SELECT 'Produto ' || g,
       round((5 + random() * 995)::numeric, 2),
       floor(random() * 500)::int,
       1 + floor(power(random(), 2) * :n_categorias)::int,
       timestamp '2026-11-01' - random() * interval '365 days'
FROM generate_series(1, :n_produtos) AS g;

-- Clientes -------------------------------------------------------------------
-- As cidades também têm peso desigual: as primeiras da lista aparecem mais.
INSERT INTO cliente (nome, email, cidade, uf, criado_em)
SELECT 'Cliente ' || s.g,
       'cliente' || s.g || '@exemplo.com',
       c.cidades[s.i],
       c.ufs[s.i],
       timestamp '2026-11-01' - random() * interval '5 years'
FROM (
    SELECT g, 1 + floor(power(random(), 1.5) * 20)::int AS i
    FROM generate_series(1, :n_clientes) AS g
) AS s
CROSS JOIN (
    SELECT ARRAY['São Paulo', 'Rio de Janeiro', 'Belo Horizonte', 'Brasília', 'Salvador',
                 'Curitiba', 'Fortaleza', 'Recife', 'Porto Alegre', 'Manaus',
                 'Goiânia', 'Belém', 'Campinas', 'Florianópolis', 'Vitória',
                 'Natal', 'João Pessoa', 'Maceió', 'Teresina', 'Cuiabá'] AS cidades,
           ARRAY['SP', 'RJ', 'MG', 'DF', 'BA', 'PR', 'CE', 'PE', 'RS', 'AM',
                 'GO', 'PA', 'SP', 'SC', 'ES', 'RN', 'PB', 'AL', 'PI', 'MT'] AS ufs
) AS c;

-- Pedidos --------------------------------------------------------------------
-- O random() fica numa subconsulta para ser sorteado uma única vez por linha
-- (o CASE abaixo precisa comparar o mesmo valor em todas as faixas).
-- valor_total é calculado depois, a partir dos itens.
INSERT INTO pedido (cliente_id, data_pedido, status, valor_total)
SELECT s.cliente_id,
       s.data_pedido,
       CASE
           WHEN s.r < 0.70 THEN 'ENTREGUE'
           WHEN s.r < 0.80 THEN 'ENVIADO'
           WHEN s.r < 0.88 THEN 'PAGO'
           WHEN s.r < 0.95 THEN 'PENDENTE'
           ELSE 'CANCELADO'
       END,
       0
FROM (
    SELECT 1 + floor(power(random(), 2) * :n_clientes)::int           AS cliente_id,
           timestamp '2026-11-01' - random() * interval '1095 days'   AS data_pedido,
           random()                                                   AS r
    FROM generate_series(1, :n_pedidos)
) AS s
ORDER BY s.data_pedido;  -- ids crescem com a data, como num sistema real

-- Itens ----------------------------------------------------------------------
-- Primeiro sorteia quantos itens cada pedido tem (subconsulta "q"); a função
-- generate_series do LATERAL depende de q.n, então é avaliada por pedido.
-- O preço unitário copia o preço do produto.
INSERT INTO item_pedido (pedido_id, produto_id, quantidade, preco_unitario)
SELECT i.pedido_id, i.produto_id, i.quantidade, pr.preco
FROM (
    SELECT q.id                                                      AS pedido_id,
           1 + floor(power(random(), 1.5) * :n_produtos)::int        AS produto_id,
           1 + floor(random() * 5)::int                              AS quantidade
    FROM (
        SELECT id, 1 + floor(random() * :max_itens)::int AS n
        FROM pedido
    ) AS q
    CROSS JOIN LATERAL generate_series(1, q.n) AS k
) AS i
JOIN produto AS pr ON pr.id = i.produto_id;

-- Valor total de cada pedido -------------------------------------------------
UPDATE pedido AS p
SET valor_total = t.total
FROM (
    SELECT pedido_id, sum(quantidade * preco_unitario) AS total
    FROM item_pedido
    GROUP BY pedido_id
) AS t
WHERE t.pedido_id = p.id;

COMMIT;

-- O UPDATE acima deixa uma versão morta de cada pedido. VACUUM FULL reescreve a
-- tabela compacta, para que os Seq Scans dos experimentos de índice não leiam
-- páginas infladas. ANALYZE atualiza as estatísticas usadas pelo planner.
VACUUM FULL pedido;
VACUUM ANALYZE;
