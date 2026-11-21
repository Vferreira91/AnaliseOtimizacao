package br.edu.aos.pedidos.config;

import java.io.IOException;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.web.util.ContentCachingResponseWrapper;

/**
 * Acrescenta a toda resposta os cabeçalhos de evidência dos experimentos:
 *
 * <ul>
 *   <li>{@code X-SQL-Count}: quantas vezes a requisição foi ao banco;</li>
 *   <li>{@code X-SQL-Ms}: soma do tempo dessas execuções, medido no JDBC;</li>
 *   <li>{@code X-Elapsed-Ms}: tempo total no servidor, incluindo a serialização do JSON.</li>
 * </ul>
 *
 * <p>O corpo fica em buffer ({@link ContentCachingResponseWrapper}) para que os cabeçalhos possam
 * ser escritos depois de o controller e a serialização terminarem. Assim, um SQL disparado durante
 * a serialização (lazy loading tardio) também entra na conta.
 */
@Component
@Order(Ordered.HIGHEST_PRECEDENCE)
public class MetricasRequisicaoFilter extends OncePerRequestFilter {

    public static final String SQL_COUNT = "X-SQL-Count";
    public static final String SQL_MS = "X-SQL-Ms";
    public static final String ELAPSED_MS = "X-Elapsed-Ms";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        ContentCachingResponseWrapper wrapper = new ContentCachingResponseWrapper(response);
        long inicio = System.nanoTime();
        ContadorSql.iniciar();
        try {
            chain.doFilter(request, wrapper);
        } finally {
            ContadorSql.Totais totais = ContadorSql.atual();
            ContadorSql.encerrar();
            long decorridoMs = (System.nanoTime() - inicio) / 1_000_000;
            wrapper.setHeader(SQL_COUNT, Long.toString(totais.consultas()));
            wrapper.setHeader(SQL_MS, Long.toString(totais.tempoMs()));
            wrapper.setHeader(ELAPSED_MS, Long.toString(decorridoMs));
            wrapper.copyBodyToResponse();
        }
    }
}
