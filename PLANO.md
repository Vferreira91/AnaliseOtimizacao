# Plano de Projeto — Otimização de Web Services

> Disciplina: Análise e Otimização de Sistemas
> Tema: Otimização de Web Services por meio de Cache, Consultas ao Banco de Dados e Testes de Desempenho
>
> Este documento registra as decisões de projeto e o roteiro de execução. O **relatório final** (entregável 7.2) será o `README.md`.

---

## 1. Visão geral

API REST simples (sem frontend) sobre um **sistema de pedidos**, construída para servir de laboratório para três experimentos:

| Item | Experimento | Evidências principais |
|---|---|---|
| 1 — Cache | Mesma consulta com e sem cache (Redis), TTL e invalidação | Tempo de resposta, `X-Cache: HIT/MISS`, nº de queries |
| 2 — Consultas | LAZY × EAGER × versões otimizadas; índices com `EXPLAIN ANALYZE` | Nº de SQL por requisição, tempo, planos de execução |
| 3 — Desempenho | Testes de carga com k6 em 10/50/100/200 VUs | Latência média, p95, p99, throughput, taxa de erros, CPU/memória |

Os três itens serão implementados (o enunciado tira 1,5 ponto de quem fizer só 2).

---

## 2. Decisões de projeto

| # | Decisão | Justificativa |
|---|---|---|
| D1 | **Java 21 + Spring Boot 3** | Recomendação do enunciado; `@Cacheable`, Spring Data JPA e Actuator prontos. |
| D2 | **JPA / Hibernate** | Oferece LAZY/EAGER, `JOIN FETCH`, `@BatchSize`, `@EntityGraph`, projeções e estatísticas de queries. |
| D3 | **PostgreSQL 16** | Não cria índice automaticamente em chaves estrangeiras (diferente do MySQL/InnoDB), o que torna o cenário "sem índice" real. `EXPLAIN (ANALYZE, BUFFERS)` é muito detalhado. |
| D4 | **Redis 7** como cache | Processo separado: permite mostrar `TTL`, `MONITOR` e `KEYS` ao vivo; o custo de rede/serialização gera discussão sobre "o cache sempre ajuda?". |
| D5 | **Grafana k6** para carga | Scripts em JavaScript, p95/p99 nativos, cenários por VUs, exportação em JSON (`handleSummary`). |
| D6 | **Docker Compose** | Postgres, Redis e a aplicação com limites fixos de CPU/memória garantem ambiente equivalente entre execuções (item 6.5). |
| D7 | **Flyway** para schema + **SQL com `generate_series`** para dados | Schema versionado; `ddl-auto` desligado (o Hibernate não cria índices por conta própria); carga de milhões de linhas em segundos e reproduzível. |
| D8 | **Executar os experimentos no Linux (Zorin OS)** | Docker nativo, sem a VM do WSL2; menos ruído de fundo (antivírus, indexação, updates) nas medições de p99. O desenvolvimento pode acontecer em qualquer SO graças ao Docker + Git. |
| D9 | **Contador de SQL por requisição** exposto em cabeçalho HTTP | `X-SQL-Count` e `X-Cache` tornam cada requisição uma evidência auto-explicativa (Postman, curl, k6). |

---

## 3. Modelo de dados

```
Categoria (50) 1──N Produto (20.000)
                         │
                         N
Cliente (10.000) 1──N Pedido (200.000) 1──N ItemPedido (~1.000.000)
```

| Tabela | Colunas principais | Volume alvo |
|---|---|---|
| `categoria` | id, nome, descricao | 50 |
| `produto` | id, nome, preco, estoque, categoria_id (FK), atualizado_em | 20.000 |
| `cliente` | id, nome, email, cidade, uf, criado_em | 10.000 |
| `pedido` | id, cliente_id (FK), data_pedido, status, valor_total | 200.000 |
| `item_pedido` | id, pedido_id (FK), produto_id (FK), quantidade, preco_unitario | ~1.000.000 (1 a 10 por pedido) |

- Distribuições propositalmente **não uniformes** (alguns clientes com muitos pedidos, status com seletividades diferentes, datas espalhadas em ~3 anos) para exercitar filtros, ordenações e o planner do Postgres.
- O volume pode ser reduzido por parâmetro no script de seed, caso a máquina não aguente.

---

## 4. Item 1 — Cache

### 4.1 Operações cacheadas

| Operação | Custo no banco | Volatilidade | TTL | Invalidação |
|---|---|---|---|---|
| `GET /api/produtos/{id}` (produto + categoria) | Baixo (busca por PK) | Média (preço/estoque mudam) | 10 min | `@CacheEvict` / `@CachePut` no `PUT /api/produtos/{id}` |
| `GET /api/relatorios/vendas-por-categoria` | Alto (agregação sobre ~1M itens) | Baixa (tolerância a atraso) | 60 s | Somente por expiração; o relatório explica o risco de dado defasado |

As duas operações foram escolhidas pelo contraste entre elas. A esperada é que o relatório ganhe muito com cache e que o produto por ID ganhe pouco ou nada, já que a busca por PK é barata e o Redis adiciona ida pela rede. Isso responde "o cache sempre melhorou o desempenho?".

### 4.2 Endpoints

```
GET  /api/produtos/{id}/sem-cache
GET  /api/produtos/{id}/com-cache
PUT  /api/produtos/{id}                 (atualiza preço/estoque e invalida o cache)
GET  /api/relatorios/vendas-por-categoria/sem-cache
GET  /api/relatorios/vendas-por-categoria/com-cache
DELETE /api/admin/cache                 (limpa o cache para controlar o estado inicial dos testes)
```

Cabeçalhos em toda resposta: `X-Cache: HIT|MISS|BYPASS`, `X-SQL-Count: n`, `X-Elapsed-Ms: t`.

### 4.3 Experimento obrigatório (3.4)

1. `GET /com-cache` → MISS, `X-SQL-Count > 0`
2. Repetir → HIT, `X-SQL-Count = 0`
3. `PUT /api/produtos/{id}` alterando o preço
4. `GET /com-cache` → MISS, preço novo (invalidação funcionou)
5. Profile `demo` com TTL curto (ex.: 20 s): mostrar `redis-cli TTL` diminuindo e a chave expirando
6. Relatório: alterar dados e mostrar o valor defasado até o TTL vencer (risco de stale data)

Evidências: sequência de requisições (Postman/curl), `redis-cli MONITOR`, logs SQL.

### 4.4 Implementação e resultados (2026-11-21)

- Cache-aside programático (`ProdutoService`, `RelatorioService`) em vez de `@Cacheable`, para a resposta saber se foi HIT ou MISS. O `RedisCacheManager` é *transaction-aware*: o evict do `PUT` só acontece depois do commit. Valores em JSON legível no Redis.
- Para o item 6 do experimento (relatório defasado) foi criada a escrita `PUT /api/pedidos/{id}/status`: cancelar um pedido muda o faturamento.
- `analise/experimento_cache.sh` roda o experimento 3.4 completo (profile `demo`, TTL 20 s), grava `docs/evidencias/cache/experimento-3.4.md` e `redis-monitor.txt` e restaura o produto e o pedido no final.
- `analise/medir_cache.sh` mede cada situação, um cliente por vez: `docs/evidencias/cache/resumo.md`. Mediana no servidor: produto sem cache 2,58 ms, MISS 2,82 ms, HIT 1,32 ms; relatório sem cache 1005 ms, MISS 1000 ms, HIT 1,23 ms.
- Diferença em relação ao esperado: mesmo a busca por PK ficou ~2× mais rápida com HIT (sem concorrência). O ganho absoluto é ~1,3 ms. Os testes de carga (Fase 4) vão mostrar se isso se mantém sob concorrência.

---

## 5. Item 2 — Otimização de consultas

### 5.1 LAZY × EAGER

`FetchType` é fixo no mapeamento, então duas entidades somente leitura serão mapeadas **na mesma tabela**:

- `PedidoLazy` → `@OneToMany(fetch = LAZY)` para itens, `@ManyToOne(fetch = LAZY)` para cliente/produto
- `PedidoEager` → as mesmas associações com `fetch = EAGER`

Todos os endpoints retornam **o mesmo JSON** (os `n` pedidos mais recentes com cliente, itens e produto) para que a comparação seja justa. Isso foi verificado: o hash do JSON é idêntico nas 8 variantes para n = 1, 100 e 1000.

Decisões de implementação:
- `FetchType` e `@BatchSize` são fixos no mapeamento, então há três famílias de entidades somente leitura (`@Immutable`) sobre as mesmas tabelas, em `domain/consulta/`: `PedidoLazy`/`ItemPedidoLazy`, `PedidoEager`/`ItemPedidoEager` e `PedidoBatch`/`ItemPedidoBatch`/`ClienteBatch`/`ProdutoBatch`. Numa ManyToOne, o `@BatchSize` vai na classe alvo; se ficasse em `Cliente`/`Produto`, o endpoint lazy perderia o N+1.
- "Mais recentes" = `ORDER BY id DESC` (o seed insere em ordem de data, e a PK indexa o id). O custo de achar os N pedidos é igual e pequeno em todas as estratégias, isolando o carregamento das associações.
- JOIN FETCH, EntityGraph e DTO limitam os pedidos numa subconsulta (`WHERE p.id IN (... LIMIT :n)`), o que dá 1 SQL. Com `setMaxResults` + fetch de coleção, o Hibernate pagina em memória (HHH90003004); isso fica demonstrado no endpoint `join-fetch-paginacao-memoria`.
- O mapeamento para o JSON acontece dentro da transação (`open-in-view: false`) e ordena os itens por id em Java.
- `default_batch_fetch_size` global **não** é usado: ele esconderia o N+1 de todos os endpoints.

| Endpoint | Estratégia | Comportamento esperado |
|---|---|---|
| `GET /api/pedidos/lazy?n=` | LAZY | 1 + N + N·M queries (N+1 clássico) |
| `GET /api/pedidos/eager?n=` | EAGER | Também N+1 com JPQL simples (selects secundários). É o alerta do enunciado de que EAGER não garante uma única consulta. |
| `GET /api/pedidos/join-fetch?n=` | JPQL `JOIN FETCH` | 1 query; discutir produto cartesiano |
| `GET /api/pedidos/join-fetch-paginacao-memoria?n=` | JOIN FETCH + `Limit` (armadilha) | 1 query sem LIMIT: traz a tabela inteira e corta em memória |
| `GET /api/pedidos/entity-graph?n=` | `@EntityGraph` | Equivalente declarativo ao JOIN FETCH |
| `GET /api/pedidos/batch?n=` | `@BatchSize(100)` | 1 + ⌈N/lote⌉ queries por associação |
| `GET /api/pedidos/dto?n=` | Projeção para DTO (JPQL) | 1 query enxuta, sem entidades gerenciadas |
| `GET /api/pedidos/nativo?n=` | SQL nativo (JdbcTemplate) | Comparar com DTO; discutir manutenção e portabilidade |

Medições para `n = 10, 100, 1000`: nº de SQL (`X-SQL-Count`, Hibernate Statistics), tempo, tamanho da resposta/linhas trazidas, ocorrência de N+1.

### 5.2 Índices

| Consulta | Índice proposto | O que demonstrar |
|---|---|---|
| Q1: `SELECT * FROM pedido WHERE cliente_id = ? ORDER BY data_pedido DESC` | `(cliente_id, data_pedido DESC)` | Seq Scan + Sort → Index Scan sem Sort |
| Q2: `WHERE data_pedido BETWEEN ? AND ? AND status = ?` | `(status, data_pedido)` | Uso do índice depende da seletividade: o planner ignora o índice quando o filtro retorna boa parte da tabela |
| Q3: JOIN `item_pedido` ↔ `pedido` por `pedido_id` | `(pedido_id)` | Impacto de FK sem índice nos joins (e nos endpoints LAZY) |

- Scripts `db/indices/criar.sql` e `db/indices/remover.sql`; sempre rodar `ANALYZE` depois.
- Evidências: `EXPLAIN (ANALYZE, BUFFERS)` antes/depois, salvos em `docs/evidencias/explain/` por `db/explain/executar.sh <rotulo>` (6 execuções, a 1ª descartada; mediana em `resumo.tsv`).
- Roteiro completo e reprodutível: `analise/experimento_consultas.sh` (EXPLAIN + endpoints + custo, sem e com índice).

Observado na rodada de 2026-11-21 (planos em `docs/evidencias/explain/`), com diferenças em relação ao esperado:
- **Q1**: com índice o planner escolheu **Bitmap Index Scan + Sort**, e não o Index Scan já ordenado que estava previsto. Mesmo assim caiu de 10,4 ms para 0,23 ms (cliente típico) e de 9,9 ms para 2,6 ms (cliente 1, com 1.971 pedidos).
- **Q2 amplo** (ENTREGUE em 2 anos): o índice **foi usado** (Index Scan, sem Sort), contra a expectativa, porque a ordem do índice (status, data_pedido) atende ao `ORDER BY data_pedido`. Caiu de 60,8 ms para 38,0 ms. Q2 seletivo: de 11,3 ms para 0,55 ms (Bitmap).
- **Q3**: os itens de um pedido caíram de 28,4 ms (Seq Scan paralelo) para 0,13 ms; o JOIN dos 100 pedidos recentes, de 138 ms para 4,9 ms. É isso que derruba o lazy/eager com n = 1000 de ~50 s para ~1 s / ~0,4 s.
- Custo dos 3 índices: +12 MB em `item_pedido` e +14 MB em `pedido`; criação em 0,6 s no total. INSERT quase não mudou; UPDATE de `status` em 20 mil pedidos foi de 79 ms para 194 ms (a coluna indexada impede o HOT update).
- Custo dos índices: tempo de `INSERT` em massa e tamanho em disco (`pg_relation_size`) com e sem eles.
- Endpoint `GET /api/clientes/{id}/pedidos` para levar Q1 ao teste de carga.

---

## 6. Item 3 — Testes de desempenho

### 6.1 Cenários

| Cenário | Variantes comparadas |
|---|---|
| C1 — Cache | sem cache · com cache frio (IDs aleatórios em 20k) · com cache quente (hot set de 100 IDs) · relatório com/sem cache |
| C2 — Persistência | lazy · eager · join-fetch · dto (n fixo, ex.: 50) |
| C3 — Índices | `/clientes/{id}/pedidos` antes e depois do índice |
| C4 (opcional) — Misto | 90% leituras / 10% `PUT` para observar invalidação sob carga |

### 6.2 Protocolo de execução

- Cargas: **10 / 50 / 100 / 200 VUs**, cada uma com 30 s de aquecimento (descartado) + 60 s de coleta. Desde a rodada 2, antes disso há 30 s de **pré-aquecimento a 10 VUs** (descartado; ver 6.5).
- **3 repetições** por combinação; relatar a média e a variação.
- Antes de cada rodada: reiniciar a aplicação, limpar ou pré-aquecer o cache conforme o cenário, registrar a contagem de linhas das tabelas.
- Limites fixos no Compose (ex.: app 2 CPUs / 1 GB; Postgres 2 CPUs / 2 GB) e nada pesado rodando em paralelo.
- Métricas: latência média, p95, p99, throughput (req/s) e taxa de erros (k6), CPU/memória (`docker stats`), conexões ativas no Postgres (`pg_stat_activity`) e pool Hikari (Actuator).
- Discussão prevista: o pool do Hikari (10 conexões por padrão) tende a virar gargalo em 200 VUs. Testar também com o pool ajustado.

### 6.3 Pipeline de resultados

```
k6 (handleSummary → JSON)  →  analise/gerar_graficos.py  →  docs/graficos/*.png  →  README.md
```

### 6.4 Implementação (2026-11-21)

- **API em container** (`app/Dockerfile`, serviço `app` no profile `carga` do compose): 2 CPUs / 1 GB, `-XX:MaxRAMPercentage=75`, pool via `DB_POOL_SIZE` (padrão 10).
- **`k6/carga.js`**: uma variante por execução; cenários `aquecimento` e `coleta` com o mesmo nº de VUs, sem pausa entre requisições (closed model). Métricas só da coleta (tag `scenario:coleta`); throughput = requisições da coleta ÷ duração da coleta. Também registra % de HIT (`X-Cache`), SQL/req (`X-SQL-Count`) e tempo no servidor (`X-Elapsed-Ms`).
- **`k6/rodar.sh`**: variantes × cargas × repetições (cada repetição é uma varredura completa). Antes de cada execução: ajusta os índices (só a variante C3 "sem-indice" roda sem eles), reinicia o container da API, limpa o cache (e pré-carrega os 100 produtos na variante "quente") e amostra `docker stats`. Saída em `k6/resultados/<rodada>/` (ignorada pelo Git).
- **`analise/gerar_graficos.py`** (venv em `analise/.venv`, `requirements.txt`): agrega as repetições e gera `resumo.csv`, `resumo.md` e um painel por cenário (p95 em escala log, throughput, erros).
- C2 usa n = 50 e roda **com** os índices (cenário realista); C1 também.

**Rodada curta de validação** (10 e 100 VUs, 5 s + 10 s, 1 repetição) revelou e corrigiu:
- `/dev/shm` de 64 MB do Docker estourava com consultas paralelas concorrentes do relatório (`could not resize shared memory segment`, 99% de erros): `shm_size: 1g` no Postgres.
- O runner sobrescrevia o nome do arquivo de resultado na variante "quente" (variável `id` reaproveitada).
- URLs com ids aleatórios geravam >100 mil séries no k6: agrupadas pela tag `name`.

Observações a confirmar na rodada completa (não são resultados finais):
- Produto: a API fica perto do limite de 2 CPUs (~160% de CPU) e o Postgres folgado, ou seja, o gargalo é a aplicação. O p95 de ~65 ms com 10 VUs, contra uma mediana de ~2–5 ms, sugere *throttling* de CPU do container (cota em janelas de 100 ms); falta verificar (`cpu.stat` do cgroup).
- Relatório sem cache: o Postgres satura as 2 CPUs; com 100 VUs o pool de 10 conexões esgota e as requisições falham após 30 s (`Connection is not available`).
- Relatório com cache numa coleta curta: todos os VUs dão MISS ao mesmo tempo no início e repetem a consulta pesada (*cache stampede*), e o cache não chega a ajudar em 10 s.

### 6.5 Rodada completa 1 e correção do protocolo (2026-11-22)

A rodada `completa` (132 execuções, 3h41) rodou sem falhas de infraestrutura. Evidências em `docs/evidencias/carga-rodada1/`: `resumo.md`, os gráficos e `diagnostico.md`. A análise mostrou:
- **Throttling confirmado** (`cpu.stat` do cgroup): nas variantes rápidas, a API esgota a cota de 2 CPUs em ~99% dos períodos de 100 ms, já com 10 VUs. Isso é coerente com p95 de 1 ms e p99 de ~40 ms a 10 VUs.
- **Aquecimento insuficiente da JVM sob alta concorrência.** Logo após o restart, 30 s a 100 VUs não bastam: com centenas de threads disputando a cota, o compilador JIT fica sem CPU. `produto-sem` a 100 VUs: 3.306 req/s na 1ª execução após o restart e ~7.250 nas seguintes. Com um pré-aquecimento de 30 s a 10 VUs, a 1ª execução já fica em ~7.250. Na rodada 1, portanto, a queda de throughput com mais VUs nas variantes limitadas pela CPU da API mede a JVM ainda aquecendo. As variantes limitadas pelo Postgres foram pouco afetadas.
- **Correção:** o `k6/rodar.sh` pré-aquece cada execução (`PREAQUECIMENTO=30s` a 10 VUs, mesma variante, cache esvaziado em seguida). A **rodada `completa2`** (~5 h) usa esse protocolo, e é dela que saem os números do relatório. A rodada 1 fica como evidência do problema, com material para a discussão de metodologia.
- **Relatório sem cache, já confirmado:** o Postgres fica saturado (200% de CPU) e o pool de 10 conexões esgota. A partir de 50 VUs, 55–91% das requisições falham (`Connection is not available, request timed out after 30000ms`, HTTP 500). A 200 VUs, algumas estouram também o timeout de 60 s do k6. O relatório com cache não teve nenhum erro.
- Os erros de `/dev/shm` no log da API são todos da rodada curta, anterior à correção.

### 6.6 Rodada completa 2: resultados (2026-11-22, 02:42–07:35)

132 execuções com pré-aquecimento, todas com saída gravada. Os pré-aquecimentos não tiveram nenhum erro. A variação entre repetições ficou pequena: na maioria das combinações, o mín–máx do throughput está a ~1–2% da média. Tabelas e gráficos estão em `docs/evidencias/carga/` (`resumo.md`, `resumo.csv`, `graficos/`). As variantes limitadas pelo Postgres repetiram a rodada 1 (LAZY a 10 VUs: 69,5 → 69,7 req/s), e as limitadas pela CPU da API subiram (produto sem cache a 200 VUs: 3.009 → 6.960). Isso confirma o diagnóstico da seção 6.5.

Base para as respostas do item 6.7 (números da rodada 2):
- **Maiores ganhos.** O cache do relatório: de 0,8 para ~6.000 req/s, e de 58–91% de erros para 0% a partir de 50 VUs. Depois, o índice em C3: de 99 para 5.810 req/s a 10 VUs, com p95 de 185 para 1,4 ms. Em C2, DTO e JOIN FETCH fazem ~9× e ~8,5× o throughput do LAZY (634,8 e 588,8 contra 69,7 req/s a 10 VUs), e EAGER ~2,9×.
- **Ganhos sob carga.** Nas variantes limitadas pelo Postgres (LAZY, EAGER, JOIN FETCH, DTO, sem índice, relatório sem cache), o throughput já fica estável a 10 VUs e a latência média cresce linearmente com os VUs, como prevê a lei de Little (LAZY a 200 VUs: 200 / 69,4 = 2,88 s; medido: 2,95 s). As proporções se mantêm: DTO/LAZY dá 9,1× a 10 VUs e 9,0× a 200. O cache de produto ganha mais com carga: +21% a 10 VUs (8.493 → 10.304) e +44% a 200 (6.960 → 10.029), porque sem cache o throughput cai com os VUs e com cache quase não cai.
- **Média × p95 × p99.** Nos endpoints rápidos, o throttling de CPU cria uma cauda (produto sem cache a 10 VUs: p95 de 0,9 ms e p99 de 39,8 ms). A partir de 50 VUs, o p95 salta para ~60–70 ms, perto do período de 100 ms da cota, enquanto a média fica em 5–14 ms. No relatório sem cache, o p99 chega a 60.000 ms (o timeout do k6). A 200 VUs, a mediana do tempo no servidor (`X-Elapsed-Ms`) de produto sem cache é 1,5 ms e a do cliente é 7,0 ms: a maior parte da espera acontece antes do controller (fila do Tomcat e CPU limitada).
- **Abaixo do esperado.**
  - O cache de produto a 10 VUs ganha só ~21%: a busca por PK já é barata e o gargalo é a CPU da API, gasta em HTTP e JSON, não o banco. O cache tira o Postgres de cena (CPU de 112% para 1%), mas não alivia a API.
  - "Frio" × "quente" deu igual (HIT de 100% em ambos na coleta): os 20 mil ids enchem o cache em segundos no aquecimento a 10 mil req/s. A fase fria existe, mas dura menos que o aquecimento.
  - EAGER continua N+1 (101 SQL/req).
  - DTO fica só ~8% acima do JOIN FETCH em throughput, mas usa bem menos CPU da API (85% contra 136% a 10 VUs).
  - Q2 amplo usou o índice, ao contrário do previsto (seção 5).
- **Gargalos.** A CPU da API: limite de 2 CPUs com throttling em ~99% dos períodos, nas variantes rápidas. A CPU do Postgres: 200% em C2, em C3 sem índice e no relatório sem cache. O pool do Hikari no relatório sem cache (`total=10, active=10, waiting=168`; falha após 30 s).
- **Menos consultas.** Reduzir de 387 para 101 e depois para 1 SQL/req levou o throughput de 69,7 para 200,9 e depois para 588,8 req/s. O ganho não é proporcional: 1 SQL com JOINs ainda satura o Postgres. Zerar as consultas com o cache muda o gargalo de lugar: do Postgres para a API.
- **Custos e riscos.**
  - Cache: dado desatualizado até o TTL ou a invalidação, memória do Redis, *cache stampede* (visto na rodada curta) e mais um componente para operar.
  - Índices: +26 MB e UPDATE de status de 79 para 194 ms.
  - DTO acopla a consulta à tela.
  - JOIN FETCH com paginação pode paginar em memória (HHH90003004).
- Não feito: testar com o pool do Hikari maior (seção 6.2, item opcional).

---

## 7. Estrutura do repositório

```
AnaliseOtimizacao/
├── app/                    # Spring Boot (Maven)
│   └── src/main/java/.../
│       ├── config/         # cache (Redis), contador de SQL, filtros de cabeçalho
│       ├── domain/         # entidades (incluindo PedidoLazy / PedidoEager)
│       ├── repository/
│       ├── service/
│       └── web/            # controllers
├── db/
│   ├── migration/          # Flyway (V1__schema.sql, ...)
│   ├── seed/               # população com generate_series
│   ├── indices/            # criar.sql / remover.sql
│   └── explain/            # consultas usadas com EXPLAIN ANALYZE
├── k6/                     # scripts por cenário + runner
├── analise/                # scripts Python para tabelas e gráficos
├── docs/
│   ├── evidencias/         # prints, saídas de EXPLAIN, logs SQL
│   └── graficos/
├── docker-compose.yml
├── PLANO.md                # este documento
└── README.md               # relatório técnico final
```

---

## 8. Preparação do ambiente (Zorin OS / Ubuntu)

```bash
# Git
sudo apt update && sudo apt install -y git curl

# Docker Engine + Compose (repositório oficial do Docker)
# https://docs.docker.com/engine/install/ubuntu/
sudo usermod -aG docker $USER   # depois, sair e entrar na sessão

# JDK 21 (via SDKMAN)
curl -s "https://get.sdkman.io" | bash
sdk install java 21-tem
sdk install maven

# k6
# https://grafana.com/docs/k6/latest/set-up/install-k6/  (repositório apt oficial)

# Python para os gráficos
sudo apt install -y python3-venv
```

Recomendações:
- Clonar o repositório **na partição do Linux** (ex.: `~/dev/`), e não na partição NTFS do Windows.
- `.gitattributes` força finais de linha LF, para que scripts `.sh` funcionem nos dois sistemas.

No Windows (se alguém do grupo desenvolver lá): Docker Desktop, JDK 21 (`winget install EclipseAdoptium.Temurin.21.JDK`), Maven e k6 (`winget install k6`).

---

## 9. Roteiro de execução

### Fase 0 — Infraestrutura
- [x] Repositório Git e plano de projeto
- [x] `docker-compose.yml` com Postgres e Redis
- [x] Publicar o repositório no GitHub: `Vferreira91/AnaliseOtimizacao`, **privado** (trabalho individual, sem colaboradores)
- [x] Preparar o ambiente no Zorin OS (Docker 29.10 + Compose 5.8, k6 2.4.0, JDK 21 Temurin + Maven 3.10.1 via SDKMAN, Python 3.12 + venv; Postgres 16.16 e Redis 7.4.12 sobem "healthy")

### Fase 1 — Base da aplicação
- [x] Projeto Spring Boot 3.5.16 (Web, Data JPA, Cache, Redis, Actuator, Flyway, PostgreSQL) em `app/`, pacote `br.edu.aos.pedidos`
- [x] Migrations do schema (sem índices além das PKs): `db/migration/V1__schema.sql`, empacotada no jar pelo `pom.xml`
- [x] Script de seed parametrizável + conferência de volumes: `db/seed/popular.sh` (seed reprodutível via `setseed`; ~55 s para o volume padrão)
- [x] Contador de SQL por requisição (proxy JDBC `datasource-proxy`) + cabeçalhos `X-SQL-Count` / `X-SQL-Ms` / `X-Elapsed-Ms`, inclusive em respostas de erro

### Fase 2 — Item 2 (consultas)
- [x] Entidades `PedidoLazy` / `PedidoEager` (+ família Batch) + DTOs de resposta
- [x] Endpoints lazy, eager, join-fetch, entity-graph, batch, dto, nativo (+ `join-fetch-paginacao-memoria` e `GET /api/clientes/{id}/pedidos`)
- [x] Tabela de nº de queries e tempo para n = 10/100/1000, sem e com índice: `docs/evidencias/consultas/resumo.md`
- [x] Scripts de índices + `EXPLAIN ANALYZE` antes/depois (Q1, Q2, Q3): `db/indices/`, `db/explain/`, `docs/evidencias/explain/`
- [x] Medição do custo dos índices (insert, update, tamanho e tempo de criação): `docs/evidencias/indices/`

### Fase 3 — Item 1 (cache)
- [x] Configuração Redis + TTL por cache + profile `demo` (`config/CacheConfig`, `app.cache.*`)
- [x] Endpoints com/sem cache, `PUT` com invalidação, limpeza de cache (+ `PUT /api/pedidos/{id}/status`)
- [x] Executar e documentar o experimento obrigatório (3.4): `docs/evidencias/cache/experimento-3.4.md`
- [x] Medição por requisição de sem cache / MISS / HIT: `docs/evidencias/cache/resumo.md`

### Fase 4 — Item 3 (carga)
- [x] Serviço da aplicação no `docker-compose.yml` (Dockerfile + limites de CPU/memória, decisão D6)
- [x] Scripts k6 dos cenários C1–C3 (`k6/carga.js`; C4 opcional não feito)
- [x] Runner que executa cargas × repetições e salva os JSON (`k6/rodar.sh`)
- [x] Script de tabelas e gráficos (`analise/gerar_graficos.py`), validado na rodada curta
- [x] Rodada completa 1 (`completa`): diagnóstico de throttling e aquecimento da JVM, com as evidências em `docs/evidencias/carga-rodada1/` (seção 6.5)
- [x] Pré-aquecimento a 10 VUs no runner, validado numa rodada mínima
- [x] Rodada completa 2 (`completa2`) com pré-aquecimento (4h53; seção 6.6)
- [x] Gerar tabelas e gráficos da rodada 2 em `docs/evidencias/carga/`
- [ ] (Opcional) Relatório sem cache com o pool do Hikari maior (`DB_POOL_SIZE`)

### Fase 5 — Entrega
- [x] README.md (relatório nas 7 seções do item 7.2), com os números conferidos contra `docs/evidencias/` e o SQL gerado pelo Hibernate em `docs/evidencias/consultas/sql-gerado/`
- [ ] Roteiro e gravação do vídeo (≤ 7 min), postado 1 dia antes da apresentação
- [ ] Ensaiar a apresentação prática (itens do 7.3)

---

## 10. Mapeamento para o relatório (README.md)

| Seção do relatório | Conteúdo vindo de |
|---|---|
| 1. Introdução | Seção 1 deste plano |
| 2. Arquitetura e tecnologias | Seções 2, 3 e 7 |
| 3. Implementação de cache | Seção 4 + resultados de C1 + respostas do item 3.5 |
| 4. Otimização das consultas | Seção 5 + EXPLAINs + resultados de C2/C3 + respostas do item 5.4 |
| 5. Testes de desempenho | Seção 6 + tabelas e gráficos |
| 6. Discussão | Respostas do item 6.7, trade-offs e custos |
| 7. Conclusão | Síntese |

---

## 11. Pendências / a decidir

- [ ] Prazo de entrega e data da apresentação
- [x] Integrantes do grupo e divisão das fases: desenvolvido individualmente (os demais alunos do grupo fazem outros trabalhos)
- [x] Nome do repositório no GitHub: `Vferreira91/AnaliseOtimizacao`, privado
