package br.edu.aos.pedidos.domain.consulta;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import org.hibernate.annotations.BatchSize;
import org.hibernate.annotations.Immutable;

/**
 * Pedido LAZY com batch fetching (somente leitura, tabela {@code pedido}).
 *
 * <p>Ao inicializar a coleção de itens de um pedido, o Hibernate aproveita e carrega a de até
 * {@link #LOTE} pedidos do contexto numa única consulta ({@code WHERE pedido_id = ANY(?)}).
 * O mesmo vale para clientes e produtos, cujo lote é definido na classe alvo
 * ({@link ClienteBatch}, {@link ProdutoBatch}). Resultado esperado: 1 + ⌈N/lote⌉ por associação.
 */
@Entity
@Immutable
@Table(name = "pedido")
public class PedidoBatch {

    public static final int LOTE = 100;

    @Id
    private Long id;

    @Column(name = "data_pedido")
    private LocalDateTime dataPedido;

    private String status;

    @Column(name = "valor_total")
    private BigDecimal valorTotal;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "cliente_id")
    private ClienteBatch cliente;

    @OneToMany(fetch = FetchType.LAZY)
    @JoinColumn(name = "pedido_id")
    @BatchSize(size = LOTE)
    private List<ItemPedidoBatch> itens = new ArrayList<>();

    protected PedidoBatch() {
    }

    public Long getId() {
        return id;
    }

    public LocalDateTime getDataPedido() {
        return dataPedido;
    }

    public String getStatus() {
        return status;
    }

    public BigDecimal getValorTotal() {
        return valorTotal;
    }

    public ClienteBatch getCliente() {
        return cliente;
    }

    public List<ItemPedidoBatch> getItens() {
        return itens;
    }
}
