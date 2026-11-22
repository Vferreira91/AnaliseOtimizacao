package br.edu.aos.pedidos.web.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/** Pedido sem cliente e sem itens, usado na listagem de pedidos de um cliente (Q1). */
public record PedidoResumoDTO(Long id, LocalDateTime dataPedido, String status,
                              BigDecimal valorTotal) {
}
