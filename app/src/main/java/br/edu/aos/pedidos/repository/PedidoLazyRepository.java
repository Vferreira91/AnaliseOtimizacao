package br.edu.aos.pedidos.repository;

import java.util.List;

import br.edu.aos.pedidos.domain.consulta.PedidoLazy;
import br.edu.aos.pedidos.service.LinhaPedido;
import br.edu.aos.pedidos.web.dto.PedidoResumoDTO;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.EntityGraph;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;
import org.springframework.data.repository.query.Param;

/**
 * Consultas sobre {@link PedidoLazy}. "Mais recentes" = maiores ids: o seed insere os pedidos em
 * ordem de data, então {@code ORDER BY id DESC} equivale a ordenar por data e usa o índice da PK.
 * Assim o custo de achar os N pedidos é o mesmo (e pequeno) em todas as estratégias, e a
 * comparação isola o carregamento das associações.
 *
 * <p>As versões otimizadas limitam os pedidos numa subconsulta ({@code IN (... LIMIT :n)}) em vez
 * de usar {@code setMaxResults}: com JOIN FETCH de coleção, {@code setMaxResults} faz o Hibernate
 * trazer TODAS as linhas e paginar em memória (aviso HHH90003004). Isso é demonstrado de propósito
 * em {@link #recentesJoinFetchPaginandoEmMemoria(Limit)}.
 */
public interface PedidoLazyRepository extends Repository<PedidoLazy, Long> {

    String SUBCONSULTA_RECENTES =
            "(select p2.id from PedidoLazy p2 order by p2.id desc limit :n)";

    /** Só os pedidos; cliente, itens e produtos ficam como proxies LAZY. */
    @Query("select p from PedidoLazy p order by p.id desc")
    List<PedidoLazy> recentes(Limit limite);

    /** Uma consulta: pedido + cliente + itens + produto via JOIN FETCH. */
    @Query("""
            select p from PedidoLazy p
              join fetch p.cliente
              left join fetch p.itens i
              left join fetch i.produto
            where p.id in """ + SUBCONSULTA_RECENTES + """
            order by p.id desc""")
    List<PedidoLazy> recentesJoinFetch(@Param("n") int n);

    /**
     * Armadilha: JOIN FETCH de coleção + limite aplicado pelo JPA. O SQL sai sem LIMIT, o banco
     * devolve todos os pedidos com todos os itens e o Hibernate corta a lista em memória.
     */
    @Query("""
            select p from PedidoLazy p
              join fetch p.cliente
              left join fetch p.itens i
              left join fetch i.produto
            order by p.id desc""")
    List<PedidoLazy> recentesJoinFetchPaginandoEmMemoria(Limit limite);

    /** Mesmo efeito do JOIN FETCH, declarado por EntityGraph em vez de escrito na JPQL. */
    @EntityGraph(attributePaths = {"cliente", "itens", "itens.produto"})
    @Query("select p from PedidoLazy p where p.id in " + SUBCONSULTA_RECENTES
            + " order by p.id desc")
    List<PedidoLazy> recentesEntityGraph(@Param("n") int n);

    /** Projeção: só as colunas da resposta, sem entidades gerenciadas. Uma linha por item. */
    @Query("""
            select new br.edu.aos.pedidos.service.LinhaPedido(
                     p.id, p.dataPedido, p.status, p.valorTotal,
                     c.id, c.nome, c.cidade, c.uf,
                     i.id, i.quantidade, i.precoUnitario,
                     pr.id, pr.nome)
            from PedidoLazy p
              join p.cliente c
              join p.itens i
              join i.produto pr
            where p.id in """ + SUBCONSULTA_RECENTES + """
            order by p.id desc, i.id""")
    List<LinhaPedido> recentesDto(@Param("n") int n);

    /**
     * Q1 do experimento de índices: {@code WHERE cliente_id = ? ORDER BY data_pedido DESC}.
     * Sem índice é Seq Scan + Sort; com {@code idx_pedido_cliente_data}, Index Scan já ordenado.
     */
    @Query("""
            select new br.edu.aos.pedidos.web.dto.PedidoResumoDTO(
                     p.id, p.dataPedido, p.status, p.valorTotal)
            from PedidoLazy p
            where p.cliente.id = :clienteId
            order by p.dataPedido desc""")
    List<PedidoResumoDTO> doCliente(@Param("clienteId") Long clienteId);
}
