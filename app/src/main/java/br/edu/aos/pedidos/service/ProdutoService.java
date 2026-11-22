package br.edu.aos.pedidos.service;

import br.edu.aos.pedidos.config.CacheConfig;
import br.edu.aos.pedidos.domain.Produto;
import br.edu.aos.pedidos.repository.ProdutoRepository;
import br.edu.aos.pedidos.web.dto.AtualizacaoProdutoDTO;
import br.edu.aos.pedidos.web.dto.ProdutoDTO;
import org.springframework.cache.Cache;
import org.springframework.cache.CacheManager;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

/**
 * Produto por id, com e sem cache (cache-aside escrito à mão).
 *
 * <p>O cache é usado de forma programática em vez de {@code @Cacheable} para que a resposta saiba
 * se foi HIT ou MISS. O fluxo é o mesmo do {@code @Cacheable}: procura no cache, e na ausência
 * consulta o banco e grava. A busca com cache não é {@code @Transactional}: num HIT nenhuma
 * conexão do pool é usada.
 */
@Service
public class ProdutoService {

    private final ProdutoRepository produtos;
    private final Cache cache;

    public ProdutoService(ProdutoRepository produtos, CacheManager cacheManager) {
        this.produtos = produtos;
        this.cache = cacheManager.getCache(CacheConfig.PRODUTOS);
    }

    public ResultadoCache<ProdutoDTO> buscarSemCache(Long id) {
        return ResultadoCache.bypass(carregar(id));
    }

    public ResultadoCache<ProdutoDTO> buscarComCache(Long id) {
        ProdutoDTO emCache = cache.get(id, ProdutoDTO.class);
        if (emCache != null) {
            return ResultadoCache.hit(emCache);
        }
        ProdutoDTO doBanco = carregar(id);
        cache.put(id, doBanco);
        return ResultadoCache.miss(doBanco);
    }

    /**
     * Atualiza preço e estoque e invalida a entrada do cache. Como o CacheManager é
     * transaction-aware, o evict só é executado depois do commit: a próxima leitura com cache
     * vai ao banco e já encontra o valor novo.
     */
    @Transactional
    public ProdutoDTO atualizar(Long id, AtualizacaoProdutoDTO dados) {
        Produto produto = produtos.buscarComCategoria(id).orElseThrow(() -> naoEncontrado(id));
        produto.atualizar(dados.preco(), dados.estoque());
        cache.evict(id);
        return ProdutoDTO.de(produto);
    }

    private ProdutoDTO carregar(Long id) {
        return produtos.buscarComCategoria(id).map(ProdutoDTO::de)
                .orElseThrow(() -> naoEncontrado(id));
    }

    private static ResponseStatusException naoEncontrado(Long id) {
        return new ResponseStatusException(HttpStatus.NOT_FOUND, "Produto " + id + " não encontrado");
    }
}
