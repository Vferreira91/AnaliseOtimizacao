package br.edu.aos.pedidos.web;

import java.util.List;

import br.edu.aos.pedidos.service.ConsultaPedidosService;
import br.edu.aos.pedidos.web.dto.PedidoDTO;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Endpoints de comparação do Item 2: os {@code n} pedidos mais recentes com cliente e itens,
 * buscados por estratégias diferentes. O JSON é o mesmo em todos; compare os cabeçalhos
 * {@code X-SQL-Count}, {@code X-SQL-Ms} e {@code X-Elapsed-Ms}.
 */
@RestController
@RequestMapping("/api/pedidos")
public class PedidoConsultaController {

    private static final String N_PADRAO = "10";
    private static final int N_MAXIMO = 2000;

    private final ConsultaPedidosService service;

    public PedidoConsultaController(ConsultaPedidosService service) {
        this.service = service;
    }

    @GetMapping("/lazy")
    public List<PedidoDTO> lazy(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.lazy(n);
    }

    @GetMapping("/eager")
    public List<PedidoDTO> eager(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.eager(n);
    }

    @GetMapping("/join-fetch")
    public List<PedidoDTO> joinFetch(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.joinFetch(n);
    }

    /** Demonstração da paginação em memória (HHH90003004). Não usar em teste de carga. */
    @GetMapping("/join-fetch-paginacao-memoria")
    public List<PedidoDTO> joinFetchPaginandoEmMemoria(
            @RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.joinFetchPaginandoEmMemoria(n);
    }

    @GetMapping("/entity-graph")
    public List<PedidoDTO> entityGraph(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.entityGraph(n);
    }

    @GetMapping("/batch")
    public List<PedidoDTO> batch(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.batch(n);
    }

    @GetMapping("/dto")
    public List<PedidoDTO> dto(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.dto(n);
    }

    @GetMapping("/nativo")
    public List<PedidoDTO> nativo(@RequestParam(defaultValue = N_PADRAO) @Min(1) @Max(N_MAXIMO) int n) {
        return service.nativo(n);
    }
}
