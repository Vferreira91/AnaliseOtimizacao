package br.edu.aos.pedidos.repository;

import java.util.List;
import java.util.Optional;

import br.edu.aos.pedidos.domain.Produto;
import br.edu.aos.pedidos.web.dto.RelatorioVendasDTO;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

public interface ProdutoRepository extends JpaRepository<Produto, Long> {

    /** Produto com a categoria numa única consulta (busca por PK: barata). */
    @Query("select p from Produto p join fetch p.categoria where p.id = :id")
    Optional<Produto> buscarComCategoria(@Param("id") Long id);

    /**
     * Faturamento por categoria dos pedidos não cancelados. Percorre todos os ~1,1 milhão de
     * itens e junta pedido, produto e categoria: é a consulta cara que justifica o cache.
     */
    @Query("""
            select new br.edu.aos.pedidos.web.dto.RelatorioVendasDTO$Linha(
                     c.id, c.nome, count(distinct p.id), sum(i.quantidade),
                     sum(i.quantidade * i.precoUnitario))
            from PedidoLazy p
              join p.itens i
              join i.produto pr
              join pr.categoria c
            where p.status <> 'CANCELADO'
            group by c.id, c.nome
            order by sum(i.quantidade * i.precoUnitario) desc""")
    List<RelatorioVendasDTO.Linha> vendasPorCategoria();
}
