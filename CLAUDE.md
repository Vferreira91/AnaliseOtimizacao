# CLAUDE.md

Contexto para o Claude Code neste repositório.

## O projeto

Trabalho prático da disciplina **Análise e Otimização de Sistemas** (Ciência da Computação): uma API REST de um sistema de pedidos usada como laboratório para três experimentos:

1. **Cache** (Redis): com/sem cache, TTL, invalidação
2. **Consultas**: LAZY × EAGER × versões otimizadas (JOIN FETCH, EntityGraph, BatchSize, DTO, SQL nativo) e índices com `EXPLAIN ANALYZE`
3. **Testes de carga** (k6): 10/50/100/200 VUs; média, p95, p99, throughput, erros

**Leia o [PLANO.md](PLANO.md) antes de qualquer tarefa.** Ele tem as decisões de projeto (seção 2), o modelo de dados, os endpoints, o protocolo dos experimentos e o checklist por fases (seção 9). Ao concluir itens do checklist, marque-os no PLANO.md.

O `README.md` será o **relatório técnico final** (entregável), com as 7 seções exigidas pelo enunciado.

## Estado atual

- Fase 0 concluída: repositório, PLANO.md e `docker-compose.yml` (Postgres 16 + Redis 7). Ambiente do Zorin OS preparado (Docker, k6, JDK 21 e Maven via SDKMAN, Python venv). Repositório no GitHub: `Vferreira91/AnaliseOtimizacao` (privado; trabalho individual, sem colaboradores).
- Fase 1 concluída: Spring Boot 3.5.16 em `app/` (pacote `br.edu.aos.pedidos`), migration `db/migration/V1__schema.sql`, seed `db/seed/popular.sh` e contador de SQL (`config/ContadorSql*`, `MetricasRequisicaoFilter`). Entidades por enquanto: `Categoria`, `Produto`, `Cliente`; endpoint de exemplo `GET /api/clientes/{id}`.
- Fase 2 concluída: famílias de entidades em `domain/consulta/`, endpoints `/api/pedidos/*` (JSON idêntico verificado), `GET /api/clientes/{id}/pedidos`, índices (`db/indices/`), EXPLAIN (`db/explain/executar.sh`) e medições (`analise/experimento_consultas.sh` → `docs/evidencias/`). Os índices de experimento estão **criados** no banco ao final do roteiro.
- Fase 3 concluída: cache-aside no Redis (`config/CacheConfig`, `ProdutoService`, `RelatorioService`), endpoints `/api/produtos/{id}/{sem,com}-cache`, `PUT /api/produtos/{id}`, `/api/relatorios/vendas-por-categoria/{sem,com}-cache`, `PUT /api/pedidos/{id}/status`, `DELETE /api/admin/cache`. Experimento 3.4 em `analise/experimento_cache.sh` (exige `SPRING_PROFILES_ACTIVE=demo`; restaura os dados ao final) e medição em `analise/medir_cache.sh`.
- Fase 4 concluída: API em container (`docker compose --profile carga up -d app`, porta 8080), `k6/carga.js`, `k6/rodar.sh` (com pré-aquecimento a 10 VUs) e `analise/gerar_graficos.py`. A rodada 1 (`completa`) foi descartada para os números porque a JVM ainda aquecia durante a coleta; o diagnóstico está em `docs/evidencias/carga-rodada1/` e no PLANO 6.5. Os resultados do relatório são da rodada 2 (`completa2`), em `docs/evidencias/carga/`, com a análise no PLANO 6.6.
- Fase 5 em andamento: `README.md` escrito como relatório final (7 seções + apêndices de reprodução e de evidências). Faltam o roteiro e a gravação do vídeo (≤ 7 min) e o ensaio da apresentação.
- Ambiente de desenvolvimento e de medição: **Linux (Zorin OS, base Ubuntu)**, com Docker nativo.

## Stack e convenções

- Java 21, Spring Boot 3, Maven (com wrapper `mvnw`), Spring Data JPA/Hibernate, Flyway, PostgreSQL 16, Redis 7, k6, Python (matplotlib) para os gráficos.
- **Idioma**: português para código de domínio (entidades, endpoints, tabelas), documentação, commits e respostas ao usuário. Termos técnicos consagrados podem ficar em inglês.
- Schema só via Flyway (`spring.jpa.hibernate.ddl-auto=validate` ou `none`). O Hibernate nunca cria tabelas ou índices.
- **Índices**: só as PKs no schema base. Índices de experimento ficam em `db/indices/criar.sql` e `db/indices/remover.sql`, para o cenário "sem índice" ser real.
- `PedidoLazy` e `PedidoEager` são entidades somente leitura mapeadas na mesma tabela `pedido`. Todos os endpoints de comparação devem devolver o **mesmo JSON**.
- Toda resposta expõe os cabeçalhos `X-SQL-Count`, `X-Elapsed-Ms` e, nos endpoints com cache, `X-Cache: HIT|MISS|BYPASS`.
- Finais de linha LF (`.gitattributes`); scripts `.sh` precisam funcionar no Linux.

## Comandos úteis

```bash
docker compose up -d                                   # Postgres + Redis
docker compose ps                                      # ambos devem estar "healthy"
docker exec -it ao-postgres psql -U app -d pedidos     # console SQL
docker exec -it ao-redis redis-cli                     # console Redis (TTL, MONITOR, KEYS)
cd app && ./mvnw spring-boot:run                       # sobe a API em :8080 (o Flyway aplica as migrations)
SPRING_PROFILES_ACTIVE=sql ./mvnw spring-boot:run      # idem, logando cada SQL do Hibernate
./db/seed/popular.sh                                   # popula o banco (N_PEDIDOS=... etc. ajustam o volume)
docker exec -i ao-postgres psql -U app -d pedidos < db/seed/conferir.sql   # só a conferência
docker compose --profile carga up -d --build app       # API em container (2 CPUs / 1 GB) para os testes de carga
./k6/rodar.sh                                          # rodada completa (RODADA, CARGAS, REPETICOES... ajustáveis)
analise/.venv/bin/python analise/gerar_graficos.py k6/resultados/<rodada>   # tabelas + gráficos
```

A API em container e a API local (`./mvnw spring-boot:run`) usam a mesma porta 8080: pare uma antes de subir a outra.

## Cuidados

- O shell não interativo do Claude não carrega o `.bashrc`: antes de usar `java`/`mvn`, rode `source ~/.sdkman/bin/sdkman-init.sh`. Se `docker` der "permission denied" (grupo ainda não ativo na sessão do app), use `sg docker -c "<comando>"`.

- Os testes de carga rodam só contra o ambiente local deste projeto.
- Resultados apresentados no relatório devem ser os **medidos de fato**. Nunca invente ou estime números.
- Faça commit só quando o usuário pedir. As mensagens de commit devem ser em português.
