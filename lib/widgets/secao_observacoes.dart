import 'package:flutter/material.dart';

import '../models/observacao_item.dart';
import 'seletor_cores_legenda.dart';

/// Seção de observações com lista de itens.
/// Cada item tem texto e cor selecionável.
/// Quando [exibirComoTopico] é true, exibe apenas o conteúdo (sem ExpansionTile).
class SecaoObservacoes extends StatefulWidget {
  final bool exibirComoTopico;

  const SecaoObservacoes({super.key, this.exibirComoTopico = false});

  @override
  State<SecaoObservacoes> createState() => SecaoObservacoesState();
}

class SecaoObservacoesState extends State<SecaoObservacoes> {
  final List<_ObservacaoControllers> _fields = [];
  bool _expandida = false;

  @override
  void initState() {
    super.initState();
    _adicionarInicial();
  }

  void _adicionarInicial() {
    final o1 = _ObservacaoControllers(cor: Colors.black);
    o1.texto.text = 'Testes hidráulicos realizados.';
    final o2 = _ObservacaoControllers(cor: Colors.black);
    o2.texto.text = 'Testes elétricos realizados.';
    final o3 = _ObservacaoControllers(cor: Colors.red);
    o3.texto.text = 'Imóvel necessita de pintura.';
    final o4 = _ObservacaoControllers(cor: Colors.red);
    o4.texto.text = 'Imóvel sem limpeza recente.';
    setState(() => _fields.addAll([o1, o2, o3, o4]));
  }

  void addObservacao() {
    setState(() => _fields.add(_ObservacaoControllers(cor: Colors.black)));
  }

  List<ObservacaoItem> getItensObservacao() {
    return _fields
        .map((o) => ObservacaoItem(
              texto: o.texto.text.trim(),
              cor: o.cor,
            ))
        .where((item) => item.texto.isNotEmpty)
        .toList();
  }

  void carregarItensObservacao(List<ObservacaoItem> itens) {
    setState(() {
      // Limpar campos existentes (incluindo templates iniciais)
      for (final f in _fields) {
        f.dispose();
      }
      _fields.clear();
      
      // Carregar itens salvos
      for (final item in itens) {
        final o = _ObservacaoControllers(cor: item.cor);
        o.texto.text = item.texto;
        _fields.add(o);
      }
      
      // Se não houver itens salvos, não adicionar templates iniciais
      // (deixar vazio para que o usuário adicione manualmente)
    });
  }

  @override
  void dispose() {
    for (final o in _fields) {
      o.dispose();
    }
    super.dispose();
  }

  void _remover(int index) {
    setState(() {
      _fields[index].dispose();
      _fields.removeAt(index);
    });
  }

  Widget _buildCard(int index) {
    final o = _fields[index];
    return Card(
      key: ValueKey('observacao_$index'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000080),
                  ),
                ),
                IconButton(
                  onPressed: () => _remover(index),
                  icon: const Icon(Icons.remove_circle_outline),
                  color: Colors.red,
                  tooltip: 'Remover item',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: o.texto,
                    decoration: const InputDecoration(
                      labelText: 'Texto da observação',
                      hintText: 'Ex: Testes hidráulicos realizados.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.analytics_outlined),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Cor:', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    SeletorCoresLegenda(
                      key: ValueKey('observacao_cor_$index'),
                      corInicial: o.cor,
                      onCorChanged: (c) => o.cor = c,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConteudo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...List.generate(_fields.length, (i) => _buildCard(i)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: addObservacao,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar observação'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF000080),
            side: const BorderSide(color: Color(0xFF00C896)),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.exibirComoTopico) {
      return _buildConteudo();
    }
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _expandida,
        onExpansionChanged: (expanded) {
          setState(() => _expandida = expanded);
        },
        leading: const Icon(Icons.visibility, color: Color(0xFF000080)),
        title: const Text(
          'OBSERVAÇÃO',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF000080),
          ),
        ),
        collapsedBackgroundColor: Colors.grey[50],
        backgroundColor: Colors.white,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Lista de observações com bullet. Cada item pode ter uma cor diferente.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 12),
                _buildConteudo(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ObservacaoControllers {
  final texto = TextEditingController();
  Color cor;

  _ObservacaoControllers({this.cor = Colors.black});

  void dispose() {
    texto.dispose();
  }
}
