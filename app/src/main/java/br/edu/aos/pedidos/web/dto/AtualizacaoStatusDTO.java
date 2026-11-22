package br.edu.aos.pedidos.web.dto;

import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;

/** Corpo do {@code PUT /api/pedidos/{id}/status}. */
public record AtualizacaoStatusDTO(
        @NotNull @Pattern(regexp = "PENDENTE|PAGO|ENVIADO|ENTREGUE|CANCELADO") String status) {
}
