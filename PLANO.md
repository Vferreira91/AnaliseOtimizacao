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

---

## 5. Item 2 — Otimização de consultas

### 5.1 LAZY × EAGER

`FetchType` é fixo no mapeamento, então duas entidades somente leitura serão mapeadas **na mesma tabela**:

- `PedidoLazy` → `@OneToMany(fetch = LAZY)` para itens, `@ManyToOne(fetch = LAZY)` para cliente/produto
- `PedidoEager` → as mesmas associações com `fetch = EAGER`

Todos os endpoints retornam **o mesmo JSON** (os `n` pedidos mais recentes com cliente, itens e produto) para que a comparação seja justa.

| Endpoint | Estratégia | Comportamento esperado |
|---|---|---|
| `GET /api/pedidos/lazy?n=` | LAZY | 1 + N + N·M queries (N+1 clássico) |
| `GET /api/pedidos/eager?n=` | EAGER | Também N+1 com `findAll`/JPQL simples (selects secundários). É o alerta do enunciado de que EAGER não garante uma única consulta. |
| `GET /api/pedidos/join-fetch?n=` | JPQL `JOIN FETCH` | 1 query; discutir produto cartesiano e paginação em memória (HHH90003004) |
| `GET /api/pedidos/entity-graph?n=` | `@EntityGraph` | Equivalente declarativo ao JOIN FETCH |
| `GET /api/pedidos/batch?n=` | `@BatchSize` / `default_batch_fetch_size` | 1 + ⌈N/lote⌉ queries |
| `GET /api/pedidos/dto?n=` | Projeção para DTO (JPQL) | 1 query enxuta, sem entidades gerenciadas |
| `GET /api/pedidos/nativo?n=` | SQL nativo | Comparar com DTO; discutir manutenção e portabilidade |

Medições para `n = 10, 100, 1000`: nº de SQL (`X-SQL-Count`, Hibernate Statistics), tempo, tamanho da resposta/linhas trazidas, ocorrência de N+1.

### 5.2 Índices

| Consulta | Índice proposto | O que demonstrar |
|---|---|---|
| Q1: `SELECT * FROM pedido WHERE cliente_id = ? ORDER BY data_pedido DESC` | `(cliente_id, data_pedido DESC)` | Seq Scan + Sort → Index Scan sem Sort |
| Q2: `WHERE data_pedido BETWEEN ? AND ? AND status = ?` | `(status, data_pedido)` | Uso do índice depende da seletividade: o planner ignora o índice quando o filtro retorna boa parte da tabela |
| Q3: JOIN `item_pedido` ↔ `pedido` por `pedido_id` | `(pedido_id)` | Impacto de FK sem índice nos joins (e nos endpoints LAZY) |

- Scripts `db/indices/criar.sql` e `db/indices/remover.sql`; sempre rodar `ANALYZE` depois.
- Evidências: `EXPLAIN (ANALYZE, BUFFERS)` antes/depois, salvos em `docs/evidencias/explain/`.
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

- Cargas: **10 / 50 / 100 / 200 VUs**, cada uma com 30 s de aquecimento (descartado) + 60 s de coleta.
- **3 repetições** por combinação; relatar a média e a variação.
- Antes de cada rodada: reiniciar a aplicação, limpar ou pré-aquecer o cache conforme o cenário, registrar a contagem de linhas das tabelas.
- Limites fixos no Compose (ex.: app 2 CPUs / 1 GB; Postgres 2 CPUs / 2 GB) e nada pesado rodando em paralelo.
- Métricas: latência média, p95, p99, throughput (req/s) e taxa de erros (k6), CPU/memória (`docker stats`), conexões ativas no Postgres (`pg_stat_activity`) e pool Hikari (Actuator).
- Discussão prevista: o pool do Hikari (10 conexões por padrão) tende a virar gargalo em 200 VUs. Testar também com o pool ajustado.

### 6.3 Pipeline de resultados

```
k6 (handleSummary → JSON)  →  analise/gerar_graficos.py  →  docs/graficos/*.png  →  README.md
```

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
- [ ] Publicar o repositório no GitHub e adicionar o grupo
- [x] Preparar o ambiente no Zorin OS (Docker 29.10 + Compose 5.8, k6 2.4.0, JDK 21 Temurin + Maven 3.10.1 via SDKMAN, Python 3.12 + venv; Postgres 16.16 e Redis 7.4.12 sobem "healthy")

### Fase 1 — Base da aplicação
- [x] Projeto Spring Boot 3.5.16 (Web, Data JPA, Cache, Redis, Actuator, Flyway, PostgreSQL) em `app/`, pacote `br.edu.aos.pedidos`
- [x] Migrations do schema (sem índices além das PKs): `db/migration/V1__schema.sql`, empacotada no jar pelo `pom.xml`
- [x] Script de seed parametrizável + conferência de volumes: `db/seed/popular.sh` (seed reprodutível via `setseed`; ~55 s para o volume padrão)
- [x] Contador de SQL por requisição (proxy JDBC `datasource-proxy`) + cabeçalhos `X-SQL-Count` / `X-SQL-Ms` / `X-Elapsed-Ms`, inclusive em respostas de erro

### Fase 2 — Item 2 (consultas)
- [ ] Entidades `PedidoLazy` / `PedidoEager` + DTOs de resposta
- [ ] Endpoints lazy, eager, join-fetch, entity-graph, batch, dto, nativo
- [ ] Tabela de nº de queries e tempo para n = 10/100/1000
- [ ] Scripts de índices + `EXPLAIN ANALYZE` antes/depois (Q1, Q2, Q3)
- [ ] Medição do custo dos índices (insert e tamanho)

### Fase 3 — Item 1 (cache)
- [ ] Configuração Redis + TTL por cache + profile `demo`
- [ ] Endpoints com/sem cache, `PUT` com invalidação, limpeza de cache
- [ ] Executar e documentar o experimento obrigatório (3.4)

### Fase 4 — Item 3 (carga)
- [ ] Serviço da aplicação no `docker-compose.yml` (Dockerfile + limites de CPU/memória, decisão D6)
- [ ] Scripts k6 dos cenários C1–C3 (+ C4 opcional)
- [ ] Runner que executa cargas × repetições e salva os JSON
- [ ] Rodada completa no Linux com o protocolo da seção 6.2
- [ ] Gerar tabelas e gráficos

### Fase 5 — Entrega
- [ ] README.md (relatório nas 7 seções do item 7.2)
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
- [ ] Integrantes do grupo e divisão das fases
- [ ] Nome do repositório no GitHub (público ou privado)
