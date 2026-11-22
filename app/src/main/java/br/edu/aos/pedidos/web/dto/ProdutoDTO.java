package br.edu.aos.pedidos.web.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

import br.edu.aos.pedidos.domain.Produto;

public record ProdutoDTO(Long id, String nome, BigDecimal preco, Integer estoque,
                         Categoria categoria, LocalDateTime atualizadoEm) {

    public record Categoria(Long id, String nome) {
    }

    /** A categoria precisa já estar carregada (JOIN FETCH) ou a transação ainda aberta. */
    public static ProdutoDTO de(Produto p) {
        return new ProdutoDTO(p.getId(), p.getNome(), p.getPreco(), p.getEstoque(),
                new Categoria(p.getCategoria().getId(), p.getCategoria().getNome()),
                p.getAtualizadoEm());
    }
}
