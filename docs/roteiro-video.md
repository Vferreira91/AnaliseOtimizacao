# Roteiro do vídeo (até 7 min)

Cobre os 8 itens da apresentação prática (enunciado, 7.3). As demonstrações são feitas por
[`analise/demo.sh`](../analise/demo.sh): cada bloco mostra o comando antes da saída e espera
**Enter** entre os passos. Assim, você controla o ritmo, e nada precisa ser digitado ao vivo.

As falas são sugestões: adapte ao seu jeito de falar. Os números citados nas falas que **não**
aparecem na tela vêm do relatório (rodada `completa2`). Os que aparecem na tela são medidos na
hora e podem variar um pouco de uma gravação para outra.

## Antes de gravar

1. Feche navegador, mensageiros e qualquer programa pesado. Silencie as notificações.
2. Suba o ambiente com a API no profile `demo` (TTL de 20 s). Todos os comandos deste roteiro
   rodam **na raiz do projeto**, onde está o `docker-compose.yml`. Fora dela, o Docker responde
   `no configuration file provided: not found`:
   ```bash
   cd ~/Desenvolvimento/AnaliseOtimizacao
   docker compose up -d
   SPRING_PROFILES_ACTIVE=demo docker compose --profile carga up -d app
   ```
3. Aqueça a JVM (~1,5 min). Sem isso, as primeiras requisições saem lentas e um HIT pode
   aparecer mais lento que um MISS:
   ```bash
   ./analise/demo.sh aquecer
   ```
4. Deixe abertos e prontos:
   - um terminal na raiz do projeto, com **fonte grande** (Ctrl + algumas vezes) e a janela
     maximizada;
   - o README no GitHub, numa aba posicionada no diagrama da seção 2.1;
   - outra aba na seção 5.5 (gráficos).
5. Faça um ensaio completo, depois rode `./analise/demo.sh aquecer` de novo e só então grave.
   O ensaio deixa o cache e o banco como estavam; o bloco `indices` recria o índice que remove.

## Linha do tempo

| Tempo | Bloco | Itens do 7.3 | Na tela |
|---|---|---|---|
| 0:00–0:30 | Abertura e arquitetura | Arquitetura simplificada | README, diagrama da seção 2.1 |
| 0:30–1:10 | Ambiente e API | Funcionamento dos Web Services | `demo.sh ambiente` e `demo.sh api` |
| 1:10–2:30 | Cache | Uso do cache e mecanismo de atualização | `demo.sh cache` |
| 2:30–3:45 | LAZY × EAGER × otimizadas | Diferenças LAZY/EAGER; consultas antes e depois | `demo.sh consultas` |
| 3:45–4:35 | Índices | Uso dos índices | `demo.sh indices` |
| 4:35–5:45 | Teste de carga | Execução de um teste de desempenho | `demo.sh carga` |
| 5:45–6:50 | Resultados e conclusões | Principais resultados e conclusões | README, gráficos da seção 5.5 |
| 6:50–7:00 | Encerramento | | README |

---

## 0:00–0:30 · Abertura e arquitetura

**Tela:** README no GitHub, diagrama da seção 2.1.

> Olá, meu nome é Vinicius, e este é o trabalho de Análise e Otimização de Sistemas: uma API REST
> de um sistema de pedidos, em Spring Boot com JPA e Hibernate, usada como laboratório para três
> otimizações: cache com Redis, otimização de consultas e índices no PostgreSQL, e testes de
> carga com k6. Tudo roda em Docker, com limites fixos de CPU e memória para que as medições
> sejam comparáveis. Cada operação existe em várias versões que devolvem exatamente o mesmo
> JSON; a única diferença entre elas é a forma de acessar os dados.

## 0:30–1:10 · Ambiente e API

**Tela:** terminal.

```bash
./analise/demo.sh ambiente
```

> Aqui estão os três containers: a API com 2 CPUs e 1 GB, o Postgres e o Redis. O banco tem
> 200 mil pedidos e 1,1 milhão de itens, gerados por script com distribuições não uniformes.

```bash
./analise/demo.sh api
```

> Toda resposta traz cabeçalhos de instrumentação: `X-SQL-Count` diz quantos comandos SQL a
> requisição executou, `X-Elapsed-Ms` o tempo dentro da API e, nos endpoints de cache,
> `X-Cache` diz se foi HIT, MISS ou BYPASS. Assim, cada requisição já é uma evidência.

## 1:10–2:30 · Cache e mecanismo de atualização

```bash
./analise/demo.sh cache
```

| Passo | Fala |
|---|---|
| 1. MISS | "Primeira consulta ao produto 42: MISS. Foi ao banco, 1 SQL, e gravou o resultado no Redis." |
| 2. HIT | "Repetindo: HIT, zero SQL. A resposta veio do Redis." |
| 3. TTL | "No Redis, a chave tem TTL. Nesta demonstração ele é de 20 s (no normal, 10 min) e está diminuindo. Ao chegar a zero, a chave expira sozinha." |
| 4. PUT | "Agora altero o preço pela API. Além de gravar no banco, o PUT remove a chave do cache, e só depois do commit. O `EXISTS` deu zero: a chave sumiu." |
| 5. MISS novo | "A próxima consulta é MISS e já traz o preço novo. Ninguém leu o valor antigo." |
| 6. Relatório | "Onde o cache rende de verdade: o relatório de vendas agrega 1,1 milhão de itens e leva cerca de 1 segundo. Com cache, cerca de 1 milissegundo. Esse relatório não é invalidado a cada pedido: ele expira pelo TTL, então pode ficar até 60 s desatualizado (20 s nesta demonstração). Para um painel gerencial isso é aceitável, e o relatório mostra esse comportamento passo a passo." |

## 2:30–3:45 · LAZY × EAGER × consultas otimizadas

```bash
./analise/demo.sh consultas
```

**Primeira tela:** a tabela com as 7 estratégias.

> A mesma requisição, os 10 pedidos mais recentes com cliente, itens e produto, em sete
> estratégias. O md5 igual mostra que o JSON é idêntico. LAZY faz 76 consultas: 1 para os
> pedidos e depois uma para os itens de cada pedido, uma para cada cliente e uma para cada
> produto. É o problema N+1. EAGER faz 21: carrega antes, mas também com consultas
> separadas. Ou seja, EAGER não significa uma consulta só. JOIN FETCH, EntityGraph, DTO e SQL
> nativo fazem 1 consulta; o batch fetching faz 4.

**Segunda tela:** o log do Postgres para LAZY com n = 2.

> Ligando o log do Postgres, dá para ver o N+1 chegando ao banco: com só 2 pedidos, são 13
> consultas, uma por produto, uma por cliente...

**Terceira tela:** JOIN FETCH com n = 2.

> ...e com JOIN FETCH é um único SELECT com os JOINs.

*(Se sobrar tempo: "Com n = 1000 e sem índice, LAZY e EAGER levaram cerca de 50 segundos; JOIN
FETCH, 151 milissegundos.")*

## 3:45–4:35 · Índices

```bash
./analise/demo.sh indices
```

> A consulta dos pedidos de um cliente, ordenados por data. Sem índice, o plano é um Seq Scan
> paralelo: o Postgres lê os 200 mil pedidos e descarta quase todos para achar 13, cerca de
> 10 ms. Crio o índice composto em cliente e data e repito: agora é um Bitmap Index Scan, que
> vai direto às 13 linhas, em menos de meio milissegundo. Um detalhe: eu esperava que o índice
> já entregasse as linhas ordenadas, mas o planner preferiu ordenar as 13 em memória. Por isso
> é preciso olhar o plano e não supor. O índice tem custo: nas medições, um UPDATE de status
> ficou 2,5 vezes mais lento.

## 4:35–5:45 · Execução de um teste de carga

```bash
./analise/demo.sh carga
```

> Agora um teste de carga com o k6: 50 usuários virtuais simultâneos, cada um fazendo
> requisições sem pausa, primeiro na versão LAZY e depois na versão DTO. Esta execução é curta,
> 15 segundos de coleta. No relatório, cada combinação teve 60 segundos e três repetições,
> foram 132 execuções em quase 5 horas.

*(Enquanto roda o LAZY:)*

> O k6 mede latência média, p95, p99, throughput e taxa de erros.

*(Resultados na tela:)*

> LAZY: cerca de 70 requisições por segundo, com média perto de 750 ms. DTO: cerca de 600
> requisições por segundo, com média em torno de 80 ms. Mesma resposta, quase 9 vezes mais
> throughput, só por trocar centenas de consultas por uma.

## 5:45–6:50 · Resultados e conclusões

**Tela:** README, seção 5.5. Role a página de cima para baixo: os quatro gráficos aparecem na
ordem abaixo, cada um com o título no alto. Todos têm três painéis: latência p95 (esquerda),
throughput (meio) e taxa de erros (direita). Em todos, o eixo horizontal é o número de usuários
simultâneos (10, 50, 100 e 200).

**Gráfico 1 de 4: "C1 · Produto por id: sem cache × com cache"** (~10 s)
*Aponte o painel do meio, Throughput: a linha azul (sem cache) fica abaixo das outras duas.*

> Primeiro, o cache na busca de um produto. A linha azul, sem cache, fica entre 7 e 8,5 mil
> requisições por segundo; com cache, cerca de 10 mil. O ganho é de só 21% a 44%: buscar por
> chave primária já é barato, e o gargalo passa a ser a CPU da própria API.

**Gráfico 2 de 4: "C1 · Relatório de vendas por categoria: sem cache × com cache"** (~15 s)
*Aponte primeiro o painel da direita, Taxa de erros (a linha azul subindo), depois o do meio,
Throughput (a linha azul colada no zero e a laranja perto de 6 mil).*

> No relatório, o cache faz toda a diferença. Sem cache, à direita, os erros sobem para 58%,
> 77% e 91% a partir de 50 usuários: as requisições esperam conexão com o banco e desistem. No
> meio, sem cache o banco conclui menos de 1 relatório por segundo. Com cache, são cerca de 6
> mil por segundo, sem nenhum erro. Foi o maior ganho do trabalho.

**Gráfico 3 de 4: "C2 · 50 pedidos com cliente e itens, por estratégia de carregamento"** (~15 s)
*Aponte o painel do meio, Throughput: quatro linhas retas, de baixo para cima LAZY, EAGER,
JOIN FETCH e DTO.*

> Agora as estratégias de consulta. No meio, de baixo para cima: LAZY, cerca de 70 requisições
> por segundo; EAGER, 200; JOIN FETCH e DTO, perto de 600. Eliminar o N+1 deu cerca de 9 vezes
> mais throughput. As linhas são retas porque o banco já está saturado: mais usuários só
> aumentam a latência, à esquerda.

**Gráfico 4 de 4: "C3 · Pedidos de um cliente (Q1): sem índice × com índice"** (~10 s)
*Aponte o painel do meio, Throughput: a linha azul (sem índice) colada no zero e a laranja
entre 5 e 6 mil.*

> Por fim, o índice. Sem índice, a consulta dos pedidos de um cliente fica em 100 requisições
> por segundo; com índice, quase 6 mil com 10 usuários, cerca de 60 vezes mais.

**Tela:** seção 6 (Discussão) ou 5.3 (o quadro sobre o pré-aquecimento).

> Duas lições:
> - **Toda otimização desloca o gargalo.** O cache tirou a carga do Postgres e a passou para a
>   API; o índice acelera a leitura e encarece a escrita.
> - **A própria medição pode enganar.** Minha primeira rodada de carga mostrou o throughput
>   caindo pela metade com mais usuários. Investigando, descobri que era a JVM ainda aquecendo:
>   com 200 threads disputando 2 CPUs, o compilador JIT ficava sem CPU. Refiz a rodada com
>   pré-aquecimento, e os números do relatório são dessa segunda rodada.

## 6:50–7:00 · Encerramento

> O código, os scripts para reproduzir cada experimento e o relatório completo estão no
> repositório. Obrigado.

---

## Trechos de código para mostrar (opcional)

Mostrar código custa tempo: com 7 minutos, escolha **no máximo 4 trechos**, de 10 a 15 s cada,
e compense cortando o bloco `ambiente` (0:30) e encurtando os resultados (5:45). Abra cada
trecho no momento do bloco correspondente, e não numa seção separada de código.

| # | Quando | Arquivo e linhas | O que dizer |
|---|---|---|---|
| 1 | Cache, antes do passo 1 | [`ProdutoService.java:38-58`](../app/src/main/java/br/edu/aos/pedidos/service/ProdutoService.java#L38-L58) | "Cache-aside: procura no Redis; se não acha, vai ao banco e grava. No PUT, o `evict` remove a chave." |
| 1b | (junto do 1, se couber) | [`CacheConfig.java:46-58`](../app/src/main/java/br/edu/aos/pedidos/config/CacheConfig.java#L46-L58) e [`application.yml:44-62`](../app/src/main/resources/application.yml#L44-L62) | "Um TTL por cache: 10 min para o produto, 60 s para o relatório. E `transactionAware`: o evict só acontece depois do commit." |
| 2 | Consultas, antes da tabela | [`PedidoLazy.java:42-48`](../app/src/main/java/br/edu/aos/pedidos/domain/consulta/PedidoLazy.java#L42-L48) ao lado de [`PedidoEager.java:42-48`](../app/src/main/java/br/edu/aos/pedidos/domain/consulta/PedidoEager.java#L42-L48) | "As duas entidades mapeiam a mesma tabela; só muda o `FetchType`." |
| 2b | (junto do 2) | [`PedidoMapper.java:35-43`](../app/src/main/java/br/edu/aos/pedidos/service/PedidoMapper.java#L35-L43) | "É aqui que o LAZY dispara as consultas: cada `getItens()`, `getCliente()` e `getProduto()` vira um SELECT." |
| 3 | Consultas, antes do log do JOIN FETCH | [`PedidoLazyRepository.java:33-42`](../app/src/main/java/br/edu/aos/pedidos/repository/PedidoLazyRepository.java#L33-L42) (JOIN FETCH) e [`:61-75`](../app/src/main/java/br/edu/aos/pedidos/repository/PedidoLazyRepository.java#L61-L75) (DTO) | "A otimização está na consulta, não no mapeamento: o JOIN FETCH traz tudo num SELECT, e o DTO traz só as colunas da resposta." |
| 4 | Índices, antes do CREATE | [`db/indices/criar.sql`](../db/indices/criar.sql) | "Os índices ficam fora do schema base, para o cenário sem índice ser real." |
| 5 | (se sobrar tempo) Carga | [`k6/carga.js:54-69`](../k6/carga.js#L54-L69) | "Dois cenários com os mesmos VUs: aquecimento, que é descartado, e coleta." |
| 6 | (se sobrar tempo) API | [`MetricasRequisicaoFilter.java:49-51`](../app/src/main/java/br/edu/aos/pedidos/config/MetricasRequisicaoFilter.java#L49-L51) | "Um filtro HTTP grava os cabeçalhos `X-SQL-Count` e `X-Elapsed-Ms`; um proxy no DataSource conta os SQL." |

Os quatro mais importantes, se precisar escolher: **1, 2, 2b e 3**. Eles mostram as duas
decisões centrais do trabalho (cache-aside com invalidação, e LAZY × EAGER × consulta otimizada),
e o 2b explica de onde vem o N+1 que o log do Postgres mostra logo em seguida.

Na IDE: aumente a fonte ou use o modo apresentação (IntelliJ: *View → Appearance → Enter
Presentation Mode*; VS Code: *View → Appearance → Zen Mode* e Ctrl + para ampliar). Feche os
painéis laterais e deixe só o editor.

## Fazendo as requisições pelo Postman (opcional)

A coleção [`docs/postman/AnaliseOtimizacao.postman_collection.json`](postman/AnaliseOtimizacao.postman_collection.json)
tem as requisições do vídeo na ordem do roteiro: API, Cache, Consultas e Índice. Todas foram
testadas contra a API. Uso:

1. Instale o Postman: `sudo snap install postman`. Use o app de **desktop**: a versão web não
   acessa `localhost` sem o agente do Postman.
2. *File → Import* (ou arraste o arquivo para a janela) e escolha o arquivo da coleção.
3. A variável `baseUrl` já aponta para `http://localhost:8080`, e `n` vale 10. Para mudar, use
   a aba *Variables* da coleção.
4. Em cada resposta, os cabeçalhos aparecem na aba **Headers**. A coleção também os resume na
   aba **Test Results** (`X-Cache: HIT`, `X-SQL-Count: 76`...), que fica mais legível no vídeo.

O que continua no terminal, porque o Postman não alcança:
- o TTL e o `EXISTS` no Redis;
- o log do Postgres com o N+1;
- o `EXPLAIN ANALYZE`;
- o k6.

Uma boa composição é a tela dividida: Postman à esquerda e terminal à direita. Nos blocos
`cache` e `consultas`, envie as requisições pelo Postman e use o terminal só para os comandos
abaixo:

```bash
docker exec ao-redis redis-cli TTL produtos::42      # cache: TTL diminuindo
docker exec ao-redis redis-cli EXISTS produtos::42   # cache: 0 depois do PUT
```

Para o N+1, o EXPLAIN e o k6, use os blocos `consultas`, `indices` e `carga` do `demo.sh`, como
no roteiro. Ao final, `./analise/demo.sh restaurar` devolve o produto 42 exatamente ao estado
do seed, inclusive a data de atualização que o PUT do Postman altera.

## Depois de gravar

```bash
./analise/demo.sh restaurar
```

Esvazia o cache, garante os índices, desliga o log de SQL do Postgres e volta a API ao profile
padrão (TTL de 10 min).

## Se algo der errado durante a gravação

| Problema | O que fazer |
|---|---|
| `curl` sem resposta / conexão recusada | A API está reiniciando: espere `curl localhost:8080/actuator/health` responder `UP` |
| HIT mais lento que MISS, LAZY muito abaixo de 70 req/s | JVM fria: rode `./analise/demo.sh aquecer` de novo |
| `no configuration file provided: not found` | O terminal não está na raiz do projeto: `cd ~/Desenvolvimento/AnaliseOtimizacao` |
| O TTL do Redis aparece como 600 | A API está no profile padrão: suba com `SPRING_PROFILES_ACTIVE=demo` (passo 2) |
| O bloco parou no meio | Rode `./analise/demo.sh restaurar`, depois `SPRING_PROFILES_ACTIVE=demo docker compose --profile carga up -d app` e `./analise/demo.sh aquecer` |
| Sem tempo para uma demonstração | Mostre a evidência gravada: [`experimento-3.4.md`](evidencias/cache/experimento-3.4.md), [`sql-gerado/lazy.txt`](evidencias/consultas/sql-gerado/lazy.txt), [`explain/`](evidencias/explain/) |

## Conferência dos itens do 7.3

| Item do 7.3 | Onde aparece |
|---|---|
| Arquitetura simplificada da aplicação | 0:00 diagrama; 0:30 containers |
| Funcionamento dos Web Services | 0:30 `api` |
| Utilização do cache e seu mecanismo de atualização | 1:10 `cache` (MISS, HIT, TTL, invalidação no PUT, relatório) |
| Diferenças entre LAZY e EAGER | 2:30 `consultas` (76 × 21 SQL; log do Postgres) |
| Comportamento das consultas antes e depois das otimizações | 2:30 `consultas` (13 SQL → 1 SQL); 4:35 `carga` |
| Utilização dos índices | 3:45 `indices` (Seq Scan → Bitmap Index Scan) |
| Execução de pelo menos um teste de desempenho | 4:35 `carga` (k6 ao vivo) |
| Principais resultados e conclusões | 5:45 gráficos e discussão |
