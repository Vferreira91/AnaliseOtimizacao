# Cache: custo por requisição (um cliente, sem concorrência)

Gerado por `analise/medir_cache.sh` + `analise/resumir_cache.py`. Tempos no servidor (`X-Elapsed-Ms`) e no cliente (curl), em ms.

| Variante | Requisições | X-Cache | SQL/req | Servidor: média | mediana | p95 | Banco (média) | Cliente: mediana |
|---|---:|---|---:|---:|---:|---:|---:|---:|
| produto-sem | 200 | BYPASS 200 | 1 | 2.69 | 2.58 | 3.08 | 0.43 | 3.50 |
| produto-miss | 200 | MISS 200 | 1 | 2.85 | 2.82 | 3.48 | 0.36 | 3.40 |
| produto-hit | 200 | HIT 200 | 0 | 1.35 | 1.32 | 1.58 | 0.00 | 1.91 |
| relatorio-sem | 20 | BYPASS 20 | 1 | 1007.57 | 1005.41 | 1044.60 | 1005.67 | 1006.41 |
| relatorio-miss | 20 | MISS 20 | 1 | 1010.06 | 999.94 | 1049.65 | 1007.46 | 1000.61 |
| relatorio-hit | 200 | HIT 200 | 0 | 1.30 | 1.23 | 1.62 | 0.00 | 1.80 |
