package br.edu.aos.pedidos.web.dto;

import java.time.LocalDateTime;

import br.edu.aos.pedidos.domain.Cliente;

public record ClienteDTO(Long id, String nome, String email, String cidade, String uf,
                         LocalDateTime criadoEm) {

    public static ClienteDTO de(Cliente c) {
        return new ClienteDTO(c.getId(), c.getNome(), c.getEmail(), c.getCidade(), c.getUf(),
                c.getCriadoEm());
    }
}
