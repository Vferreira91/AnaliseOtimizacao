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
 * Pedido com todas as associações EAGER (somente leitura, tabela {@code pedido}).
 *
 * <p>EAGER diz apenas QUE os dados virão junto, não COMO. Numa consulta JPQL simples o Hibernate
 * executa a consulta principal e depois um select secundário por associação de cada pedido,
 * ou seja, também pode haver N+1. O comportamento observado é medido pelo cabeçalho X-SQL-Count.
 */
@Entity
@Immutable
@Table(name = "pedido")
public class PedidoEager {

    @Id
    private Long id;

    @Column(name = "data_pedido")
    private LocalDateTime dataPedido;

    private String status;

    @Column(name = "valor_total")
    private BigDecimal valorTotal;

    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "cliente_id")
    private Cliente cliente;

    @OneToMany(fetch = FetchType.EAGER)
    @JoinColumn(name = "pedido_id")
    private List<ItemPedidoEager> itens = new ArrayList<>();

    protected PedidoEager() {
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

    public List<ItemPedidoEager> getItens() {
        return itens;
    }
}
