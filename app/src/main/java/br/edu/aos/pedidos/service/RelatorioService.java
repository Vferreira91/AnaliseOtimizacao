package br.edu.aos.pedidos.service;

import java.time.LocalDateTime;
import java.time.temporal.ChronoUnit;

import br.edu.aos.pedidos.config.CacheConfig;
import br.edu.aos.pedidos.repository.ProdutoRepository;
import br.edu.aos.pedidos.web.dto.RelatorioVendasDTO;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.stereotype.Service;

/**
 * Relatório de vendas por categoria, com e sem cache.
 *
 * <p>Não há invalidação: uma mudança nos pedidos (ex.: cancelamento) só aparece na versão com
 * cache quando a entrada expira pelo TTL. É uma escolha deliberada para um dado caro e
 * tolerante a atraso; o risco de exibir números defasados é discutido no relatório.
 */
@Service
public class RelatorioService {

    /** Uma única entrada: o relatório não tem parâmetros. */
    private static final String CHAVE = "todas";

    private final ProdutoRepository produtos;
    private final Cache cache;

    public RelatorioService(ProdutoRepository produtos, CacheManager cacheManager) {
        this.produtos = produtos;
        this.cache = cacheManager.getCache(CacheConfig.RELATORIO_VENDAS);
    }

    public ResultadoCache<RelatorioVendasDTO> semCache() {
        return ResultadoCache.bypass(gerar());
    }

    public ResultadoCache<RelatorioVendasDTO> comCache() {
        RelatorioVendasDTO emCache = cache.get(CHAVE, RelatorioVendasDTO.class);
        if (emCache != null) {
            return ResultadoCache.hit(emCache);
        }
        RelatorioVendasDTO novo = gerar();
        cache.put(CHAVE, novo);
        return ResultadoCache.miss(novo);
    }

    private RelatorioVendasDTO gerar() {
        return new RelatorioVendasDTO(LocalDateTime.now().truncatedTo(ChronoUnit.MILLIS),
                produtos.vendasPorCategoria());
    }
}
