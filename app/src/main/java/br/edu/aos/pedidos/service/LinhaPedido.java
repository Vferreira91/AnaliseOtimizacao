package br.edu.aos.pedidos.service;

import java.math.BigDecimal;
import java.time.LocalDateTime;

/**
 * Uma linha "achatada" pedido × item, usada pelas versões DTO (JPQL) e SQL nativo.
 * Cada linha traz o pedido, o cliente, um item e o produto desse item.
 */
public record LinhaPedido(Long pedidoId, LocalDateTime dataPedido, String status,
                          BigDecimal valorTotal, Long clienteId, String clienteNome,
                          String clienteCidade, String clienteUf, Long itemId, Integer quantidade,
                          BigDecimal precoUnitario, Long produtoId, String produtoNome) {
}
