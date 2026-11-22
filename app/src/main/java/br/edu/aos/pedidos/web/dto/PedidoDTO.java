package br.edu.aos.pedidos.web.dto;

import java.math.BigDecimal;
import java.time.LocalDateTime;
import java.util.List;

/**
 * Resposta única de todos os endpoints de comparação ({@code /api/pedidos/*}). Qualquer que seja a
 * estratégia de busca, o JSON produzido é idêntico; só mudam o SQL executado e o tempo.
 */
public record PedidoDTO(Long id, LocalDateTime dataPedido, String status, BigDecimal valorTotal,
                        Cliente cliente, List<Item> itens) {

    public record Cliente(Long id, String nome, String cidade, String uf) {
    }

    public record Item(Long id, Integer quantidade, BigDecimal precoUnitario, Produto produto) {
    }

    public record Produto(Long id, String nome) {
    }
}
