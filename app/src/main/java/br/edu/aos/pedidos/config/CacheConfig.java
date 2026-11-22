package br.edu.aos.pedidos.config;

import java.time.Duration;

import br.edu.aos.pedidos.web.dto.ProdutoDTO;
import br.edu.aos.pedidos.web.dto.RelatorioVendasDTO;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.data.redis.cache.RedisCacheConfiguration;
import org.springframework.data.redis.cache.RedisCacheManager;
import org.springframework.data.redis.connection.RedisConnectionFactory;
import org.springframework.data.redis.serializer.Jackson2JsonRedisSerializer;
import org.springframework.data.redis.serializer.RedisSerializationContext.SerializationPair;

/**
 * Cache no Redis com um TTL por cache.
 *
 * <ul>
 *   <li>{@value #PRODUTOS}: produto + categoria por id. Volatilidade média (preço e estoque
 *       mudam), por isso TTL moderado e invalidação explícita no {@code PUT}.</li>
 *   <li>{@value #RELATORIO_VENDAS}: agregação sobre ~1,1 milhão de itens. Caro de calcular e
 *       tolerante a atraso: só expira pelo TTL, sem invalidação.</li>
 * </ul>
 *
 * <p>Os valores ficam em JSON legível (dá para inspecionar com {@code redis-cli GET}). O gerenciador
 * é <em>transaction-aware</em>: um {@code evict} feito dentro de uma transação só acontece depois
 * do commit. Sem isso, outra requisição poderia ler o valor antigo do banco entre o evict e o
 * commit e repovoar o cache com ele.
 */
@Configuration(proxyBeanMethods = false)
@EnableConfigurationProperties(CacheConfig.Ttl.class)
public class CacheConfig {

    public static final String PRODUTOS = "produtos";
    public static final String RELATORIO_VENDAS = "relatorio-vendas";

    /** TTLs, configuráveis em {@code app.cache.*} (o profile {@code demo} encurta os dois). */
    @ConfigurationProperties("app.cache")
    public record Ttl(Duration produtos, Duration relatorioVendas) {
    }

    @Bean
    RedisCacheManager cacheManager(RedisConnectionFactory conexao, ObjectMapper mapper, Ttl ttl) {
        RedisCacheConfiguration base = RedisCacheConfiguration.defaultCacheConfig()
                .disableCachingNullValues();
        return RedisCacheManager.builder(conexao)
                .withCacheConfiguration(PRODUTOS, base
                        .entryTtl(ttl.produtos())
                        .serializeValuesWith(json(mapper, ProdutoDTO.class)))
                .withCacheConfiguration(RELATORIO_VENDAS, base
                        .entryTtl(ttl.relatorioVendas())
                        .serializeValuesWith(json(mapper, RelatorioVendasDTO.class)))
                .disableCreateOnMissingCache()
                .transactionAware()
                .build();
    }

    private static <T> SerializationPair<T> json(ObjectMapper mapper, Class<T> tipo) {
        return SerializationPair.fromSerializer(new Jackson2JsonRedisSerializer<>(mapper, tipo));
    }
}
