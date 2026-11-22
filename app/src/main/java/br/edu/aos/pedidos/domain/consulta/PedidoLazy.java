package br.edu.aos.pedidos.domain.consulta;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

import br.edu.aos.pedidos.domain.Cliente;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;
import org.hibernate.annotations.Immutable;

/**
 * Pedido com todas as associações LAZY (somente leitura, tabela {@code pedido}).
 *
 * <p>Cliente, itens e o produto de cada item só são buscados quando acessados. Percorrer N pedidos
 * gera o N+1 clássico. Também é a base dos endpoints JOIN FETCH, EntityGraph e DTO, que mudam o
 * carregamento na consulta sem mexer no mapeamento.
 */
@Entity
@Immutable
@Table(name = "pedido")
public class PedidoLazy {

    @Id
    private Long id;

    @Column(name = "data_pedido")
    private LocalDateTime dataPedido;

    private String status;

    @Column(name = "valor_total")
    private BigDecimal valorTotal;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "cliente_id")
    private Cliente cliente;

    @OneToMany(fetch = FetchType.LAZY)
    @JoinColumn(name = "pedido_id")
    private List<ItemPedidoLazy> itens = new ArrayList<>();

    protected PedidoLazy() {
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

    public Cliente getCliente() {
        return cliente;
    }

    public List<ItemPedidoLazy> getItens() {
        return itens;
    }
}
