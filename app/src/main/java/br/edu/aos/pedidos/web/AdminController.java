package br.edu.aos.pedidos.web;

import org.springframework.cache.CacheManager;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/** Operações de apoio aos experimentos. */
@RestController
@RequestMapping("/api/admin")
public class AdminController {

    private final CacheManager cacheManager;

    public AdminController(CacheManager cacheManager) {
        this.cacheManager = cacheManager;
    }

    /** Esvazia todos os caches, para começar uma medição com o cache frio. */
    @DeleteMapping("/cache")
    public ResponseEntity<Void> limparCache() {
        for (String nome : cacheManager.getCacheNames()) {
            cacheManager.getCache(nome).clear();
        }
        return ResponseEntity.noContent().build();
    }
}
