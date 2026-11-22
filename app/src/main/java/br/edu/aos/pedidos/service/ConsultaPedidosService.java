package br.edu.aos.pedidos.service;

import java.util.List;

import br.edu.aos.pedidos.repository.PedidoBatchRepository;
import br.edu.aos.pedidos.repository.PedidoEagerRepository;
import br.edu.aos.pedidos.repository.PedidoLazyRepository;
import br.edu.aos.pedidos.web.dto.PedidoDTO;
import org.springframework.data.domain.Limit;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

/**
 * As estratégias de busca comparadas no Item 2. Todas devolvem os {@code n} pedidos mais recentes
 * com cliente, itens e produto de cada item, no mesmo {@link PedidoDTO}.
 */
@Service
@Transactional(readOnly = true)
public class ConsultaPedidosService {

    /**
     * SQL escrito à mão. Limita os pedidos numa subconsulta e junta as demais tabelas.
     * Equivale ao que a versão DTO gera, mas fica preso ao dialeto (LIMIT) e aos nomes físicos.
     */
    static final String SQL_NATIVO = """
            SELECT p.id, p.data_pedido, p.status, p.valor_total,
                   c.id, c.nome, c.cidade, c.uf,
                   i.id, i.quantidade, i.preco_unitario,
                   pr.id, pr.nome
            FROM (SELECT id, cliente_id, data_pedido, status, valor_total
                  FROM pedido
                  ORDER BY id DESC
                  LIMIT ?) p
            JOIN cliente c      ON c.id = p.cliente_id
            JOIN item_pedido i  ON i.pedido_id = p.id
            JOIN produto pr     ON pr.id = i.produto_id
            ORDER BY p.id DESC, i.id
            """;

    private final PedidoLazyRepository lazy;
    private final PedidoEagerRepository eager;
    private final PedidoBatchRepository batch;
    private final JdbcTemplate jdbc;

    public ConsultaPedidosService(PedidoLazyRepository lazy, PedidoEagerRepository eager,
                                  PedidoBatchRepository batch, JdbcTemplate jdbc) {
        this.lazy = lazy;
        this.eager = eager;
        this.batch = batch;
        this.jdbc = jdbc;
    }

    public List<PedidoDTO> lazy(int n) {
        return lazy.recentes(Limit.of(n)).stream().map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> eager(int n) {
        return eager.recentes(Limit.of(n)).stream().map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> joinFetch(int n) {
        return lazy.recentesJoinFetch(n).stream().map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> joinFetchPaginandoEmMemoria(int n) {
        return lazy.recentesJoinFetchPaginandoEmMemoria(Limit.of(n)).stream()
                .map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> entityGraph(int n) {
        return lazy.recentesEntityGraph(n).stream().map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> batch(int n) {
        return batch.recentes(Limit.of(n)).stream().map(PedidoMapper::de).toList();
    }

    public List<PedidoDTO> dto(int n) {
        return PedidoMapper.deLinhas(lazy.recentesDto(n));
    }

    public List<PedidoDTO> nativo(int n) {
        List<LinhaPedido> linhas = jdbc.query(SQL_NATIVO, (rs, i) -> new LinhaPedido(
                rs.getLong(1), rs.getObject(2, java.time.LocalDateTime.class), rs.getString(3),
                rs.getBigDecimal(4),
                rs.getLong(5), rs.getString(6), rs.getString(7), rs.getString(8),
                rs.getLong(9), rs.getInt(10), rs.getBigDecimal(11),
                rs.getLong(12), rs.getString(13)), n);
        return PedidoMapper.deLinhas(linhas);
    }
}
