package br.edu.aos.pedidos.web;

import java.util.Map;

import br.edu.aos.pedidos.web.dto.AtualizacaoStatusDTO;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

/**
 * Altera o status de um pedido. Serve ao experimento de cache: cancelar um pedido muda o
 * relatório de vendas, mas a versão com cache só reflete isso quando a entrada expira.
 *
 * <p>Usa SQL direto porque as entidades de pedido ({@code PedidoLazy} etc.) são somente leitura.
 */
@RestController
@RequestMapping("/api/pedidos")
public class PedidoStatusController {

    private final JdbcTemplate jdbc;

    public PedidoStatusController(JdbcTemplate jdbc) {
        this.jdbc = jdbc;
    }

    @PutMapping("/{id}/status")
    public Map<String, Object> alterar(@PathVariable Long id, @Valid @RequestBody AtualizacaoStatusDTO dados) {
        int linhas = jdbc.update("UPDATE pedido SET status = ? WHERE id = ?", dados.status(), id);
        if (linhas == 0) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "Pedido " + id + " não encontrado");
        }
        return Map.of("id", id, "status", dados.status());
    }
}
