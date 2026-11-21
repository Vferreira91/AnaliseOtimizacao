package br.edu.aos.pedidos.repository;

import br.edu.aos.pedidos.domain.Cliente;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ClienteRepository extends JpaRepository<Cliente, Long> {
}
