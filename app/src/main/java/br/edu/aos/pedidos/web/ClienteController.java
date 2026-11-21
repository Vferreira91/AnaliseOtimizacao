package br.edu.aos.pedidos.web;

import br.edu.aos.pedidos.repository.ClienteRepository;
import br.edu.aos.pedidos.web.dto.ClienteDTO;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.server.ResponseStatusException;

@RestController
@RequestMapping("/api/clientes")
public class ClienteController {

    private final ClienteRepository clientes;

    public ClienteController(ClienteRepository clientes) {
        this.clientes = clientes;
    }

    @GetMapping("/{id}")
    public ClienteDTO buscar(@PathVariable Long id) {
        return clientes.findById(id)
                .map(ClienteDTO::de)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND,
                        "Cliente " + id + " não encontrado"));
    }
}
