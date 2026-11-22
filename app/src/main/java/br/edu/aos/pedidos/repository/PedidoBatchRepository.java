package br.edu.aos.pedidos.repository;

import java.util.List;

import br.edu.aos.pedidos.domain.consulta.PedidoBatch;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;

public interface PedidoBatchRepository extends Repository<PedidoBatch, Long> {

    /** Igual à versão LAZY; a diferença está no {@code @BatchSize} do mapeamento. */
    @Query("select p from PedidoBatch p order by p.id desc")
    List<PedidoBatch> recentes(Limit limite);
}
