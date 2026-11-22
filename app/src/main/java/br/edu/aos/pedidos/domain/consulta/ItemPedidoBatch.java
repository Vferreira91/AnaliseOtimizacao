package br.edu.aos.pedidos.domain.consulta;

import java.math.BigDecimal;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;
import org.hibernate.annotations.Immutable;

/** Item de pedido da família batch (somente leitura, tabela {@code item_pedido}). */
@Entity
@Immutable
@Table(name = "item_pedido")
public class ItemPedidoBatch {

    @Id
    private Long id;

    private Integer quantidade;

    @Column(name = "preco_unitario")
    private BigDecimal precoUnitario;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "produto_id")
    private ProdutoBatch produto;

    protected ItemPedidoBatch() {
    }

    public Long getId() {
        return id;
    }

    public Integer getQuantidade() {
        return quantidade;
    }

    public BigDecimal getPrecoUnitario() {
        return precoUnitario;
    }

    public ProdutoBatch getProduto() {
        return produto;
    }
}
