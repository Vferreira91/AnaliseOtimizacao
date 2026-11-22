package br.edu.aos.pedidos.service;

/**
 * Valor devolvido por uma operação cacheável e de onde ele veio. O controller transforma o
 * status no cabeçalho {@code X-Cache}.
 */
public record ResultadoCache<T>(T valor, Status status) {

    public enum Status {
        /** Encontrado no cache; o banco não foi consultado. */
        HIT,
        /** Ausente no cache; consultado no banco e gravado no cache. */
        MISS,
        /** Endpoint sem cache; consultado no banco. */
        BYPASS
    }

    public static <T> ResultadoCache<T> hit(T valor) {
        return new ResultadoCache<>(valor, Status.HIT);
    }

    public static <T> ResultadoCache<T> miss(T valor) {
        return new ResultadoCache<>(valor, Status.MISS);
    }

    public static <T> ResultadoCache<T> bypass(T valor) {
        return new ResultadoCache<>(valor, Status.BYPASS);
    }
}
