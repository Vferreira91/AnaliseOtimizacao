package br.edu.aos.pedidos.service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import br.edu.aos.pedidos.domain.Cliente;
import br.edu.aos.pedidos.domain.Produto;
import br.edu.aos.pedidos.domain.consulta.ClienteBatch;
import br.edu.aos.pedidos.domain.consulta.ItemPedidoBatch;
import br.edu.aos.pedidos.domain.consulta.ItemPedidoEager;
import br.edu.aos.pedidos.domain.consulta.ItemPedidoLazy;
import br.edu.aos.pedidos.domain.consulta.PedidoBatch;
import br.edu.aos.pedidos.domain.consulta.PedidoEager;
import br.edu.aos.pedidos.domain.consulta.PedidoLazy;
import br.edu.aos.pedidos.domain.consulta.ProdutoBatch;
import br.edu.aos.pedidos.web.dto.PedidoDTO;

/**
 * Converte cada família de entidades (e as linhas achatadas) no mesmo {@link PedidoDTO}.
 *
 * <p>Deve ser chamado dentro da transação: é aqui que o acesso a {@code getCliente()},
 * {@code getItens()} e {@code getProduto()} dispara o lazy loading. Os itens são ordenados por id
 * em Java, para que a ordem do JSON não dependa do SQL de cada estratégia.
 */
final class PedidoMapper {

    private static final Comparator<PedidoDTO.Item> POR_ID = Comparator.comparing(PedidoDTO.Item::id);

    private PedidoMapper() {
    }

    static PedidoDTO de(PedidoLazy p) {
        List<PedidoDTO.Item> itens = new ArrayList<>();
        for (ItemPedidoLazy i : p.getItens()) {
            itens.add(new PedidoDTO.Item(i.getId(), i.getQuantidade(), i.getPrecoUnitario(),
                    produto(i.getProduto())));
        }
        return new PedidoDTO(p.getId(), p.getDataPedido(), p.getStatus(), p.getValorTotal(),
                cliente(p.getCliente()), ordenar(itens));
    }

    static PedidoDTO de(PedidoEager p) {
        List<PedidoDTO.Item> itens = new ArrayList<>();
        for (ItemPedidoEager i : p.getItens()) {
            itens.add(new PedidoDTO.Item(i.getId(), i.getQuantidade(), i.getPrecoUnitario(),
                    produto(i.getProduto())));
        }
        return new PedidoDTO(p.getId(), p.getDataPedido(), p.getStatus(), p.getValorTotal(),
                cliente(p.getCliente()), ordenar(itens));
    }

    static PedidoDTO de(PedidoBatch p) {
        List<PedidoDTO.Item> itens = new ArrayList<>();
        for (ItemPedidoBatch i : p.getItens()) {
            ProdutoBatch pr = i.getProduto();
            itens.add(new PedidoDTO.Item(i.getId(), i.getQuantidade(), i.getPrecoUnitario(),
                    new PedidoDTO.Produto(pr.getId(), pr.getNome())));
        }
        ClienteBatch c = p.getCliente();
        return new PedidoDTO(p.getId(), p.getDataPedido(), p.getStatus(), p.getValorTotal(),
                new PedidoDTO.Cliente(c.getId(), c.getNome(), c.getCidade(), c.getUf()),
                ordenar(itens));
    }

    /** Agrupa as linhas pedido × item (já ordenadas por pedido) em pedidos com seus itens. */
    static List<PedidoDTO> deLinhas(List<LinhaPedido> linhas) {
        Map<Long, List<PedidoDTO.Item>> itensPorPedido = new LinkedHashMap<>();
        Map<Long, LinhaPedido> primeiraLinha = new LinkedHashMap<>();
        for (LinhaPedido l : linhas) {
            primeiraLinha.putIfAbsent(l.pedidoId(), l);
            itensPorPedido.computeIfAbsent(l.pedidoId(), k -> new ArrayList<>())
                    .add(new PedidoDTO.Item(l.itemId(), l.quantidade(), l.precoUnitario(),
                            new PedidoDTO.Produto(l.produtoId(), l.produtoNome())));
        }
        List<PedidoDTO> pedidos = new ArrayList<>(primeiraLinha.size());
        for (LinhaPedido l : primeiraLinha.values()) {
            pedidos.add(new PedidoDTO(l.pedidoId(), l.dataPedido(), l.status(), l.valorTotal(),
                    new PedidoDTO.Cliente(l.clienteId(), l.clienteNome(), l.clienteCidade(),
                            l.clienteUf()),
                    ordenar(itensPorPedido.get(l.pedidoId()))));
        }
        return pedidos;
    }

    private static PedidoDTO.Cliente cliente(Cliente c) {
        return new PedidoDTO.Cliente(c.getId(), c.getNome(), c.getCidade(), c.getUf());
    }

    private static PedidoDTO.Produto produto(Produto pr) {
        return new PedidoDTO.Produto(pr.getId(), pr.getNome());
    }

    private static List<PedidoDTO.Item> ordenar(List<PedidoDTO.Item> itens) {
        itens.sort(POR_ID);
        return itens;
    }
}
