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

- Fase 0 concluída: repositório, PLANO.md e `docker-compose.yml` (Postgres 16 + Redis 7). Ambiente do Zorin OS preparado (Docker, k6, JDK 21 e Maven via SDKMAN, Python venv). Falta só publicar no GitHub.
- Fase 1 concluída: Spring Boot 3.5.16 em `app/` (pacote `br.edu.aos.pedidos`), migration `db/migration/V1__schema.sql`, seed `db/seed/popular.sh` e contador de SQL (`config/ContadorSql*`, `MetricasRequisicaoFilter`). Entidades por enquanto: `Categoria`, `Produto`, `Cliente`; endpoint de exemplo `GET /api/clientes/{id}`.
- **Próximo passo: Fase 2** (consultas): `PedidoLazy` / `PedidoEager`, endpoints de comparação, índices e `EXPLAIN ANALYZE`.
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
```

## Cuidados

- O shell não interativo do Claude não carrega o `.bashrc`: antes de usar `java`/`mvn`, rode `source ~/.sdkman/bin/sdkman-init.sh`. Se `docker` der "permission denied" (grupo ainda não ativo na sessão do app), use `sg docker -c "<comando>"`.

- Os testes de carga rodam só contra o ambiente local deste projeto.
- Resultados apresentados no relatório devem ser os **medidos de fato**. Nunca invente ou estime números.
- Faça commit só quando o usuário pedir. As mensagens de commit devem ser em português.
