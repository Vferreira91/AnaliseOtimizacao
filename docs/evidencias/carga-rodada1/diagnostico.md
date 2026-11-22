# Rodada 1 de carga: diagnóstico e por que foi refeita

A rodada `completa` (21/11/2026, 22:43–02:25; 132 execuções; tabelas e gráficos em
[resumo.md](resumo.md)) seguiu o protocolo original: reiniciar a API, 30 s de aquecimento
**já na carga-alvo** e 60 s de coleta. A análise dos números revelou dois fenômenos.
Um deles invalida a curva de throughput × VUs das variantes limitadas pela CPU da API,
e por isso a rodada foi refeita (`completa2`) com um pré-aquecimento a 10 VUs.

## 1. Throttling de CPU (CFS) no container da API: confirmado

O container `ao-app` tem `cpus: "2"`, ou seja, `cpu.max = 200000 100000`: 200 ms de CPU a
cada período de 100 ms. Medido no `cpu.stat` do cgroup, antes e depois de 20 s de coleta
(k6 contra a API já aquecida):

| Variante | VUs | Períodos | Períodos com throttling | CPU usada |
|---|---:|---:|---:|---:|
| produto-com-quente | 10 | 212 | 210 (99%) | 42,1 s em ~21 s |
| produto-com-quente | 100 | 213 | 211 (99%) | 41,9 s em ~21 s |
| produto-sem | 10 | 212 | 210 (99%) | 42,1 s em ~21 s |
| produto-sem | 100 | 212 | 210 (99%) | 41,9 s em ~21 s |

Nas variantes rápidas, a API esgota a cota de 2 CPUs em praticamente todo período de
100 ms, mesmo com 10 VUs. Quando a cota acaba, todas as threads esperam o próximo período.
Isso é coerente com a cauda observada a 10 VUs, por exemplo produto sem cache com p95 de
1,0 ms e p99 de 40,9 ms. A ligação requisição a requisição entre cauda e throttling não
foi medida.

## 2. Aquecimento insuficiente da JVM sob alta concorrência: invalidou a rodada 1

Com a JVM já aquecida, `produto-sem` a 100 VUs fazia ~7.200 req/s, mas na rodada 1 fez
3.776. Teste: reiniciar a API e rodar três vezes seguidas (30 s de aquecimento + 60 s de
coleta, a 100 VUs, sem reiniciar entre elas):

| Execução após o restart | Req/s | Média (ms) | p95 (ms) | p99 (ms) |
|---|---:|---:|---:|---:|
| 1ª (igual ao protocolo da rodada 1) | 3.306,3 | 30,1 | 93,8 | 106,3 |
| 2ª | 7.244,5 | 13,7 | 67,1 | 77,5 |
| 3ª | 7.306,9 | 13,6 | 66,6 | 76,8 |

Interpretação: com 100–200 threads de requisição disputando a cota de 2 CPUs, as threads
do compilador JIT (C2) recebem uma fatia pequena da CPU. A JVM continua em código
interpretado ou C1 bem depois dos 30 s de aquecimento. A 10 VUs, 30 s bastam.

Correção testada: reiniciar a API, rodar 30 s a 10 VUs (pré-aquecimento) e depois o
protocolo normal na carga-alvo.

| produto-sem | Rodada 1 | Com pré-aquecimento a 10 VUs |
|---|---:|---:|
| 100 VUs | 3.775,9 req/s | 7.268,3 req/s |
| 200 VUs | 3.009,4 req/s | 6.952,0 req/s (validação do runner: 6.918,5) |
| produto-com-frio, 200 VUs | 3.724,6 req/s | 9.992,0 req/s (validação do runner, coleta de 30 s) |

**Consequência:** na rodada 1, a queda de throughput com o aumento de VUs nas variantes
limitadas pela CPU da API (produto, relatório com cache, pedidos do cliente com índice)
mede sobretudo a JVM ainda aquecendo, não o regime estável. As variantes limitadas pelo
Postgres (relatório sem cache, LAZY, EAGER, DTO, pedidos do cliente sem índice), que têm
throughput praticamente constante, são pouco afetadas.

O `k6/rodar.sh` passou a pré-aquecer cada execução (`PREAQUECIMENTO=30s` a 10 VUs, mesma
variante, métricas descartadas, cache esvaziado em seguida). Os resultados do relatório
vêm da rodada `completa2`.

## 3. Erros do relatório sem cache: esgotamento do pool de conexões

Todos os erros da rodada vêm de `relatorio-sem` com 50, 100 ou 200 VUs. A consulta de
agregação leva vários segundos com o Postgres saturado (200% de CPU). Com o pool do
Hikari em 10 conexões, as demais requisições esperam por uma conexão e desistem após
30 s, com HTTP 500. Mensagem no log da API:

```
Connection is not available, request timed out after 30000ms (total=10, active=10, idle=0, waiting=168)
```

Além disso, a 200 VUs, 10 requisições por repetição estouraram o timeout de 60 s do
próprio k6 (`k6-erros.log`).

Os erros `could not resize shared memory segment` presentes no log da API são todos da
rodada curta de validação, anterior ao `shm_size: 1g` do Postgres. Nenhum ocorreu na
rodada completa: no log com timestamps, todos estão antes das 01:43 UTC, início da rodada.
