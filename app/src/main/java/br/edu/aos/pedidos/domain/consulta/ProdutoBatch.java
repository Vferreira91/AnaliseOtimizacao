package br.edu.aos.pedidos.domain.consulta;

import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.BatchSize;
import org.hibernate.annotations.Immutable;

/** Produto da família batch (somente leitura, tabela {@code produto}); ver {@link ClienteBatch}. */
@Entity
@Immutable
@Table(name = "produto")
@BatchSize(size = PedidoBatch.LOTE)
public class ProdutoBatch {

    @Id
    private Long id;

    private String nome;

    protected ProdutoBatch() {
    }

    public Long getId() {
        return id;
    }

    public String getNome() {
        return nome;
    }
}
