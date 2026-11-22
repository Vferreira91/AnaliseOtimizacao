# Experimento 3.4: comportamento do cache

Gerado por `analise/experimento_cache.sh` em 2026-11-21T21:34:29-03:00. Produto 42, pedido 200000.
Valores medidos nesta execução; o cache foi esvaziado antes de começar.

## A. Produto: reaproveitamento, invalidação e expiração

| Passo | Requisição | X-Cache | X-SQL-Count | X-Elapsed-Ms | Valor observado |
|---|---|---|---:|---:|---|
| A1 consulta | `GET /api/produtos/42/com-cache` | MISS | 1 | 5.03 | 244.88 |
| A2 repete | `GET /api/produtos/42/com-cache` | HIT | 0 | 2.47 | 244.88 |
| A3 altera | `PUT /api/produtos/42` |  | 2 | 5.66 | 299.9 |
| A4 consulta | `GET /api/produtos/42/com-cache` | MISS | 1 | 4.77 | 299.9 |
| A5 repete | `GET /api/produtos/42/com-cache` | HIT | 0 | 2.04 | 299.9 |

- TTL da chave `produtos::42` logo após o 1º MISS: **20 s** (profile da API).
- `EXISTS produtos::42` logo após o PUT: **0** (0 = a entrada foi invalidada).

Expiração (TTL lido no Redis enquanto o tempo passa):

- t = 0 s: TTL = 20 s
- t = 5 s: TTL = 15 s
- t = 21 s: TTL = -2 (-2 = a chave não existe mais), EXISTS = 0

| Passo | Requisição | X-Cache | X-SQL-Count | X-Elapsed-Ms | Valor observado |
|---|---|---|---:|---:|---|
| A6 após expirar | `GET /api/produtos/42/com-cache` | MISS | 1 | 4.49 | 299.9 |

## B. Relatório: dado defasado até o TTL vencer

O relatório não é invalidado por escritas. Cancelar o pedido 200000 (status original: ENTREGUE) muda o faturamento, mas a versão com cache continua servindo o valor antigo até expirar.

| Passo | Requisição | X-Cache | X-SQL-Count | X-Elapsed-Ms | Valor observado |
|---|---|---|---:|---:|---|
| B1 consulta | `GET /api/relatorios/vendas-por-categoria/com-cache` | MISS | 1 | 1037.40 | geradoEm=2026-11-21T21:34:50.731, faturamento total=1578644739.33 |
| B2 cancela pedido | `PUT /api/pedidos/200000/status` |  | 1 | 3.09 | CANCELADO |
| B3 com cache | `GET /api/relatorios/vendas-por-categoria/com-cache` | HIT | 0 | 3.30 | geradoEm=2026-11-21T21:34:50.731, faturamento total=1578644739.33 |
| B4 sem cache | `GET /api/relatorios/vendas-por-categoria/sem-cache` | BYPASS | 1 | 979.51 | geradoEm=2026-11-21T21:34:51.875, faturamento total=1578639271.81 |

Esperando 19 s para a entrada do relatório expirar...

| Passo | Requisição | X-Cache | X-SQL-Count | X-Elapsed-Ms | Valor observado |
|---|---|---|---:|---:|---|
| B5 após expirar | `GET /api/relatorios/vendas-por-categoria/com-cache` | MISS | 1 | 989.83 | geradoEm=2026-11-21T21:35:12.963, faturamento total=1578639271.81 |

Ao final, o produto, o pedido e o cache foram restaurados ao estado original.
