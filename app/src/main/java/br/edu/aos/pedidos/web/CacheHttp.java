package br.edu.aos.pedidos.web;

import br.edu.aos.pedidos.service.ResultadoCache;
import org.springframework.http.ResponseEntity;

/** Monta a resposta HTTP com o cabeçalho {@code X-Cache: HIT|MISS|BYPASS}. */
final class CacheHttp {

    static final String X_CACHE = "X-Cache";

    private CacheHttp() {
    }

    static <T> ResponseEntity<T> responder(ResultadoCache<T> resultado) {
        return ResponseEntity.ok()
                .header(X_CACHE, resultado.status().name())
                .body(resultado.valor());
    }
}
