package br.edu.aos.pedidos.web.dto;

import java.math.BigDecimal;

import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Digits;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;

/** Corpo do {@code PUT /api/produtos/{id}}. */
public record AtualizacaoProdutoDTO(
        @NotNull @DecimalMin("0.00") @Digits(integer = 10, fraction = 2) BigDecimal preco,
        @NotNull @Min(0) Integer estoque) {
}
