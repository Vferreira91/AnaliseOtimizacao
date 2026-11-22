package br.edu.aos.pedidos.config;

/**
 * Contador de SQL da requisição corrente, guardado por thread.
 *
 * <p>O {@link MetricasRequisicaoFilter} abre a contagem no início da requisição e a fecha no
 * final; o proxy JDBC ({@link ContadorSqlDataSourceConfig}) registra cada execução no meio.
 * Execuções fora de uma requisição (Flyway, inicialização do Hibernate) são ignoradas.
 *
 * <p>Cada {@code execute}/{@code executeQuery}/{@code executeUpdate}/{@code executeBatch}
 * conta como 1, ou seja, o número de idas ao banco. O tempo é medido em nanossegundos, porque
 * uma consulta por PK leva bem menos de 1 ms e somar milissegundos inteiros daria zero.
 */
public final class ContadorSql {

    /** Totais acumulados de uma requisição. */
    public static final class Totais {
        private long consultas;
        private long tempoNanos;
        private long inicioAtual;

        public long consultas() {
            return consultas;
        }

        public double tempoMs() {
            return tempoNanos / 1_000_000.0;
        }
    }

    private static final ThreadLocal<Totais> ATUAL = new ThreadLocal<>();

    private ContadorSql() {
    }

    public static void iniciar() {
        ATUAL.set(new Totais());
    }

    /** Chamado pelo proxy imediatamente antes de o SQL ir ao banco. */
    public static void antesDaExecucao() {
        Totais totais = ATUAL.get();
        if (totais != null) {
            totais.inicioAtual = System.nanoTime();
        }
    }

    /** Chamado pelo proxy quando o banco devolve o resultado. */
    public static void depoisDaExecucao() {
        Totais totais = ATUAL.get();
        if (totais != null) {
            totais.consultas++;
            totais.tempoNanos += System.nanoTime() - totais.inicioAtual;
        }
    }

    /** Totais até agora, ou {@code null} se não houver requisição em andamento nesta thread. */
    public static Totais atual() {
        return ATUAL.get();
    }

    public static void encerrar() {
        ATUAL.remove();
    }
}
