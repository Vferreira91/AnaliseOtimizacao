package br.edu.aos.pedidos.web;

import br.edu.aos.pedidos.service.ProdutoService;
import br.edu.aos.pedidos.web.dto.AtualizacaoProdutoDTO;
import br.edu.aos.pedidos.web.dto.ProdutoDTO;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Item 1 (cache): produto por id. Compare {@code X-Cache} e {@code X-SQL-Count}. */
@RestController
@RequestMapping("/api/produtos")
public class ProdutoController {

    private final ProdutoService service;

    public ProdutoController(ProdutoService service) {
        this.service = service;
    }

    @GetMapping("/{id}/sem-cache")
    public ResponseEntity<ProdutoDTO> semCache(@PathVariable Long id) {
        return CacheHttp.responder(service.buscarSemCache(id));
    }

    @GetMapping("/{id}/com-cache")
    public ResponseEntity<ProdutoDTO> comCache(@PathVariable Long id) {
        return CacheHttp.responder(service.buscarComCache(id));
    }

    /** Atualiza preço e estoque e invalida o produto no cache. */
    @PutMapping("/{id}")
    public ProdutoDTO atualizar(@PathVariable Long id, @Valid @RequestBody AtualizacaoProdutoDTO dados) {
        return service.atualizar(id, dados);
    }
}
