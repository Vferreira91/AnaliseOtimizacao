package br.edu.aos.pedidos.config;

import java.util.List;

import javax.sql.DataSource;

import net.ttddyy.dsproxy.ExecutionInfo;
import net.ttddyy.dsproxy.QueryInfo;
import net.ttddyy.dsproxy.listener.QueryExecutionListener;
import net.ttddyy.dsproxy.support.ProxyDataSource;
import net.ttddyy.dsproxy.support.ProxyDataSourceBuilder;
import org.springframework.beans.factory.config.BeanPostProcessor;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Envolve o DataSource (Hikari) num proxy JDBC que avisa o {@link ContadorSql} a cada execução.
 *
 * <p>Como a contagem acontece no nível do JDBC, ela vale para qualquer forma de acesso: entidades,
 * JPQL, {@code JOIN FETCH}, SQL nativo ou JdbcTemplate. É isso que torna os números das diferentes
 * estratégias comparáveis entre si.
 */
@Configuration(proxyBeanMethods = false)
public class ContadorSqlDataSourceConfig {

    @Bean
    static BeanPostProcessor contadorSqlDataSourcePostProcessor() {
        return new BeanPostProcessor() {
            @Override
            public Object postProcessAfterInitialization(Object bean, String beanName) {
                if (bean instanceof DataSource dataSource && !(bean instanceof ProxyDataSource)) {
                    return ProxyDataSourceBuilder.create(dataSource)
                            .name("pedidos")
                            .listener(new ContadorListener())
                            .build();
                }
                return bean;
            }
        };
    }

    private static final class ContadorListener implements QueryExecutionListener {

        @Override
        public void beforeQuery(ExecutionInfo execInfo, List<QueryInfo> queryInfoList) {
            // nada a fazer antes da execução
        }

        @Override
        public void afterQuery(ExecutionInfo execInfo, List<QueryInfo> queryInfoList) {
            ContadorSql.registrar(execInfo.getElapsedTime());
        }
    }
}
