package br.edu.aos.pedidos.web;

import java.util.List;

import br.edu.aos.pedidos.repository.ClienteRepository;
import br.edu.aos.pedidos.repository.PedidoLazyRepository;
import br.edu.aos.pedidos.web.dto.ClienteDTO;
import br.edu.aos.pedidos.web.dto.PedidoResumoDTO;
import org.springframework.http.HttpStatus;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/clientes")
public class ClienteController {

    private final ClienteRepository clientes;
    private final PedidoLazyRepository pedidos;

    public ClienteController(ClienteRepository clientes, PedidoLazyRepository pedidos) {
        this.clientes = clientes;
        this.pedidos = pedidos;
    }

    @GetMapping("/{id}")
    public ClienteDTO buscar(@PathVariable Long id) {
        return clientes.findById(id)
                .map(ClienteDTO::de)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Cliente " + id + " não encontrado"));
    }

    /**
     * Pedidos do cliente, do mais recente ao mais antigo (Q1 do experimento de índices).
     * Uma única consulta; um cliente sem pedidos devolve lista vazia.
     */
    @GetMapping("/{id}/pedidos")
    @Transactional(readOnly = true)
    public List<PedidoResumoDTO> pedidos(@PathVariable Long id) {
        return pedidos.doCliente(id);
    }
}
