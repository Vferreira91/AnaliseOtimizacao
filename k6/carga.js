// Teste de carga de uma variante (Fase 4). Normalmente chamado por k6/rodar.sh.
//
//   k6 run -e VARIANTE=produto-sem -e VUS=50 -e AQUECIMENTO=30s -e COLETA=60s \
//          -e SAIDA=/caminho/resultado.json k6/carga.js
//
// Dois cenários em sequência com o mesmo número de VUs:
//   aquecimento: JIT, pool de conexões e cache do Postgres esquentam; métricas descartadas
//   coleta:      só daqui saem as métricas do relatório (filtradas pela tag scenario:coleta)
//
// Cada VU faz requisições em sequência, sem pausa (closed model): VUs simultâneos ≠ req/s.

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';
const VARIANTE = __ENV.VARIANTE;
const VUS = parseInt(__ENV.VUS || '10', 10);
const AQUECIMENTO = __ENV.AQUECIMENTO || '30s';
const COLETA = __ENV.COLETA || '60s';
const N_PEDIDOS = __ENV.N_PEDIDOS || '50';
const SAIDA = __ENV.SAIDA || 'resultado.json';

const aleatorio = (min, max) => min + Math.floor(Math.random() * (max - min + 1));

// Variante -> gerador do caminho da próxima requisição.
const VARIANTES = {
  // C1, cache
  'produto-sem': () => `/api/produtos/${aleatorio(1, 20000)}/sem-cache`,
  'produto-com-frio': () => `/api/produtos/${aleatorio(1, 20000)}/com-cache`, // cache começa vazio
  'produto-com-quente': () => `/api/produtos/${aleatorio(1, 100)}/com-cache`, // 100 ids pré-carregados
  'relatorio-sem': () => '/api/relatorios/vendas-por-categoria/sem-cache',
  'relatorio-com': () => '/api/relatorios/vendas-por-categoria/com-cache',
  // C2, estratégias de persistência
  'pedidos-lazy': () => `/api/pedidos/lazy?n=${N_PEDIDOS}`,
  'pedidos-eager': () => `/api/pedidos/eager?n=${N_PEDIDOS}`,
  'pedidos-join-fetch': () => `/api/pedidos/join-fetch?n=${N_PEDIDOS}`,
  'pedidos-dto': () => `/api/pedidos/dto?n=${N_PEDIDOS}`,
  // C3, índices (mesma requisição; o runner muda o estado do banco)
  'cliente-pedidos-sem-indice': () => `/api/clientes/${aleatorio(1, 10000)}/pedidos`,
  'cliente-pedidos-com-indice': () => `/api/clientes/${aleatorio(1, 10000)}/pedidos`,
};

if (!VARIANTES[VARIANTE]) {
  throw new Error(`VARIANTE inválida: "${VARIANTE}". Opções: ${Object.keys(VARIANTES).join(', ')}`);
}
const proximoCaminho = VARIANTES[VARIANTE];

// Métricas lidas dos cabeçalhos da API.
const cacheHit = new Rate('cache_hit'); // X-Cache: HIT (só em endpoints com cache)
const sqlPorReq = new Trend('sql_por_req'); // X-SQL-Count
const tempoServidor = new Trend('tempo_servidor', true); // X-Elapsed-Ms

export const options = {
  scenarios: {
    aquecimento: {
      executor: 'constant-vus',
      vus: VUS,
      duration: AQUECIMENTO,
      gracefulStop: '0s',
    },
    coleta: {
      executor: 'constant-vus',
      vus: VUS,
      duration: COLETA,
      startTime: AQUECIMENTO,
      gracefulStop: '30s',
    },
  },
  // Thresholds sempre verdadeiros: servem só para o k6 calcular as submétricas da fase de coleta.
  thresholds: {
    'http_req_duration{scenario:coleta}': ['max>=0'],
    'http_reqs{scenario:coleta}': ['count>=0'],
    'http_req_failed{scenario:coleta}': ['rate>=0'],
    'cache_hit{scenario:coleta}': ['rate>=0'],
    'sql_por_req{scenario:coleta}': ['avg>=0'],
    'tempo_servidor{scenario:coleta}': ['avg>=0'],
  },
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  // tag `name` fixa: agrupa as URLs com ids aleatórios numa só série de métricas
  const res = http.get(`${BASE_URL}${proximoCaminho()}`, { timeout: '60s', tags: { name: VARIANTE } });
  check(res, { 'status 200': (r) => r.status === 200 });

  const xCache = res.headers['X-Cache'];
  if (xCache === 'HIT' || xCache === 'MISS') cacheHit.add(xCache === 'HIT');
  const sql = res.headers['X-Sql-Count'];
  if (sql !== undefined) sqlPorReq.add(Number(sql));
  const servidor = res.headers['X-Elapsed-Ms'];
  if (servidor !== undefined) tempoServidor.add(Number(servidor));
}

const segundos = (d) => {
  const m = /^(\d+(?:\.\d+)?)(ms|s|m)$/.exec(d);
  if (!m) throw new Error(`duração não suportada: ${d}`);
  return Number(m[1]) * { ms: 0.001, s: 1, m: 60 }[m[2]];
};

// Grava só o que interessa da fase de coleta, num JSON por execução.
export function handleSummary(data) {
  const v = (nome) => (data.metrics[nome] ? data.metrics[nome].values : null);
  const duracao = v('http_req_duration{scenario:coleta}');
  const reqs = v('http_reqs{scenario:coleta}');
  const falhas = v('http_req_failed{scenario:coleta}');
  const coletaS = segundos(COLETA);
  const resultado = {
    variante: VARIANTE,
    vus: VUS,
    repeticao: Number(__ENV.REPETICAO || 1),
    aquecimento: AQUECIMENTO,
    coleta_s: coletaS,
    n_pedidos: VARIANTE.startsWith('pedidos-') ? Number(N_PEDIDOS) : null,
    requisicoes: reqs ? reqs.count : 0,
    throughput_rps: reqs ? reqs.count / coletaS : 0,
    taxa_erros: falhas ? falhas.rate : null,
    latencia_ms: duracao, // avg, min, med, p(90), p(95), p(99), max
    tempo_servidor_ms: v('tempo_servidor{scenario:coleta}'),
    cache_hit: v('cache_hit{scenario:coleta}'),
    sql_por_req: v('sql_por_req{scenario:coleta}'),
    inicio_coleta_offset_s: segundos(AQUECIMENTO),
  };
  const lat = duracao || {};
  const linha = `${VARIANTE} ${VUS} VUs: ${resultado.throughput_rps.toFixed(1)} req/s, ` +
    `média ${(lat.avg || 0).toFixed(1)} ms, p95 ${(lat['p(95)'] || 0).toFixed(1)} ms, ` +
    `p99 ${(lat['p(99)'] || 0).toFixed(1)} ms, erros ${((resultado.taxa_erros || 0) * 100).toFixed(2)}%\n`;
  return { [SAIDA]: JSON.stringify(resultado, null, 2), stdout: linha };
}
