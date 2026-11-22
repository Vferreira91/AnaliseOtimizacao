package br.edu.aos.pedidos.domain.consulta;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import org.hibernate.annotations.BatchSize;
import org.hibernate.annotations.Immutable;
import org.hibernate.annotations.JdbcTypeCode;
import org.hibernate.type.SqlTypes;

/**
 * Cliente da família batch (somente leitura, tabela {@code cliente}).
 *
 * <p>Para uma associação ManyToOne, o {@code @BatchSize} vai na classe da entidade alvo. Por isso
 * existe esta cópia: se a anotação ficasse em {@code Cliente}, o endpoint LAZY também passaria a
 * carregar em lote e o N+1 deixaria de aparecer.
 */
@Entity
@Immutable
@Table(name = "cliente")
@BatchSize(size = PedidoBatch.LOTE)
public class ClienteBatch {

    @Id
    private Long id;

    private String nome;

    private String cidade;

    @Column(length = 2)
    @JdbcTypeCode(SqlTypes.CHAR)
    private String uf;

    protected ClienteBatch() {
    }

    public Long getId() {
        return id;
    }

    public String getNome() {
        return nome;
    }

    public String getCidade() {
        return cidade;
    }

    public String getUf() {
        return uf;
    }
}
