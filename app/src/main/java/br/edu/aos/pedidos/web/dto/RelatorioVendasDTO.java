package br.edu.aos.pedidos.web.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Faturamento por categoria (pedidos não cancelados). {@code geradoEm} é o instante em que o
 * relatório foi calculado no banco: numa resposta vinda do cache ele fica no passado, o que deixa
 * visível a idade (e o possível atraso) da informação.
 */
public record RelatorioVendasDTO(LocalDateTime geradoEm, List<Linha> categorias) {

    public record Linha(Long categoriaId, String categoria, Long pedidos, Long unidades,
                        BigDecimal faturamento) {
    }
}
