package br.edu.aos.pedidos.repository;

import java.util.List;

import br.edu.aos.pedidos.domain.consulta.PedidoEager;
import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.Repository;

public interface PedidoEagerRepository extends Repository<PedidoEager, Long> {

    /** JPQL simples: as associações EAGER são resolvidas pelo Hibernate depois da consulta. */
    @Query("select p from PedidoEager p order by p.id desc")
    List<PedidoEager> recentes(Limit limite);
}
