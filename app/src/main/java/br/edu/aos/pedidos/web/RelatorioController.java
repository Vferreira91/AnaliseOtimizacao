package br.edu.aos.pedidos.web;

import br.edu.aos.pedidos.service.RelatorioService;
import br.edu.aos.pedidos.web.dto.RelatorioVendasDTO;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Item 1 (cache): relatório caro, cacheado só com TTL. */
@RestController
@RequestMapping("/api/relatorios/vendas-por-categoria")
public class RelatorioController {

    private final RelatorioService service;

    public RelatorioController(RelatorioService service) {
        this.service = service;
    }

    @GetMapping("/sem-cache")
    public ResponseEntity<RelatorioVendasDTO> semCache() {
        return CacheHttp.responder(service.semCache());
    }

    @GetMapping("/com-cache")
    public ResponseEntity<RelatorioVendasDTO> comCache() {
        return CacheHttp.responder(service.comCache());
    }
}
