package br.edu.aos.pedidos.config;

/**
 * Contador de SQL da requisição corrente, guardado por thread.
 *
 * <p>O {@link MetricasRequisicaoFilter} abre a contagem no início da requisição e a fecha no
 * final; o proxy JDBC ({@link ContadorSqlDataSourceConfig}) registra cada execução no meio.
 * Execuções fora de uma requisição (Flyway, inicialização do Hibernate) são ignoradas.
 *
 * <p>Cada {@code execute}/{@code executeQuery}/{@code executeUpdate}/{@code executeBatch}
 * conta como 1, ou seja, o número de idas ao banco.
 */
public final class ContadorSql {

    /** Totais acumulados de uma requisição. */
    public static final class Totais {
        private long consultas;
        private long tempoMs;

        public long consultas() {
            return consultas;
        }

        public long tempoMs() {
            return tempoMs;
        }
    }

    private static final ThreadLocal<Totais> ATUAL = new ThreadLocal<>();

    private ContadorSql() {
    }

    public static void iniciar() {
        ATUAL.set(new Totais());
    }

    public static void registrar(long tempoMs) {
        Totais totais = ATUAL.get();
        if (totais != null) {
            totais.consultas++;
            totais.tempoMs += tempoMs;
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
