import 'package:flutter/material.dart';

import '../models/legenda.dart';
import 'seletor_cores_legenda.dart';

/// Seção de legendas com estado próprio.
/// Evita rebuild do formulário inteiro e do PDF ao adicionar/remover legendas.
class SecaoLegendas extends StatefulWidget {
  const SecaoLegendas({super.key});

  @override
  State<SecaoLegendas> createState() => SecaoLegendasState();
}

/// Estado exposto para que a HomePage possa obter as legendas.
class SecaoLegendasState extends State<SecaoLegendas> {
  final List<_LegendaControllers> _fields = [];
  bool _expandida = false;
  TipoLegenda _tipoLegenda = TipoLegenda.inconformidade;

  @override
  void initState() {
    super.initState();
    _adicionarInicial();
  }

  void _adicionarInicial() {
    final l = _LegendaControllers(cor: Colors.red);
    l.valor.text = 'INCONFORMIDADE';
    l.texto.text =
        'Item que apresenta observações visuais, com avarias e/ou necessidade de reparos, manutenções e/ou pintura, podendo ter seu funcionamento e/ou uso comprometido ou não, devendo cada situação ser avaliada individualmente.';
    setState(() => _fields.add(l));
  }

  void addLegenda() {
    setState(() => _fields.add(_LegendaControllers(cor: Colors.red)));
  }

  void _usarLegendaPadrao() {
    for (final l in _fields) {
      l.dispose();
    }
    _fields.clear();
    
    if (_tipoLegenda == TipoLegenda.status) {
      // Legenda de Status (NOVO, BOM, REGULAR, etc.)
      const padrao = [
        ('NOVO', Colors.green, 'Nunca utilizado. (Para itens parede e tetos este status se refere a pintura nova realizada no imóvel).'),
        ('BOM', Colors.blue, 'Em perfeito estado de utilização ou com observações visuais não/pouco relevantes.'),
        ('REGULAR', Colors.yellow, 'Com observações visuais relevantes sem comprometer o utilização.'),
        ('NÃO TESTADO', Colors.grey, 'Item que não foi possível realizar os testes com o mesmo em funcionamento, devido a falta de energia, água ou outro impeditivo no local.'),
        ('RUIM', Colors.red, 'Com uso comprometido ou apresentando risco ao utilizar.'),
      ];
      for (final (v, c, t) in padrao) {
        final l = _LegendaControllers(cor: c);
        l.valor.text = v;
        l.texto.text = t;
        _fields.add(l);
      }
    } else {
      // Legenda de Inconformidade (padrão inicial)
      final l = _LegendaControllers(cor: Colors.red);
      l.valor.text = 'INCONFORMIDADE';
      l.texto.text = 'Item que apresenta observações visuais, com avarias e/ou necessidade de reparos, manutenções e/ou pintura, podendo ter seu funcionamento e/ou uso comprometido ou não, devendo cada situação ser avaliada individualmente.';
      _fields.add(l);
    }
    setState(() {});
  }
  
  TipoLegenda getTipoLegenda() => _tipoLegenda;
  
  void setTipoLegenda(TipoLegenda tipo, {bool aplicarPadrao = true}) {
    setState(() {
      _tipoLegenda = tipo;
      if (aplicarPadrao) {
        _usarLegendaPadrao();
      }
    });
  }
  
  void carregarLegendas(List<Legenda> legendas) {
    for (final l in _fields) {
      l.dispose();
    }
    _fields.clear();
    
    for (final leg in legendas) {
      final l = _LegendaControllers(cor: leg.cor);
      l.valor.text = leg.valor;
      l.texto.text = leg.texto;
      _fields.add(l);
    }
    setState(() {});
  }

  List<Legenda> getLegendas() {
    return _fields
        .map((l) => Legenda(
              valor: l.valor.text.trim(),
              cor: l.cor,
              texto: l.texto.text.trim(),
            ))
        .where((l) => l.valor.isNotEmpty || l.texto.isNotEmpty)
        .toList();
  }

  @override
  void dispose() {
    for (final l in _fields) {
      l.dispose();
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
    final l = _fields[index];
    return Card(
      key: ValueKey('legenda_$index'),
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
            TextField(
              controller: l.valor,
              decoration: const InputDecoration(
                labelText: 'Título da legenda',
                hintText: 'Ex: INCONFORMIDADE',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Cor: ', style: TextStyle(fontSize: 14)),
                SeletorCoresLegenda(
                  key: ValueKey('legenda_cor_$index'),
                  corInicial: l.cor,
                  onCorChanged: (c) => l.cor = c,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: l.texto,
              decoration: const InputDecoration(
                labelText: 'Texto da legenda',
                hintText: 'Descrição do item...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.text_fields),
                isDense: true,
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: _expandida,
        onExpansionChanged: (expanded) {
          setState(() => _expandida = expanded);
        },
        leading: const Icon(Icons.legend_toggle, color: Color(0xFF000080)),
        title: const Text(
          'Legenda',
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
                // Seletor de tipo de legenda
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Tipo de Legenda',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF000080),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<TipoLegenda>(
                              title: const Text('Entrada'),
                              subtitle: const Text('NOVO, BOM, REGULAR, etc.'),
                              value: TipoLegenda.status,
                              groupValue: _tipoLegenda,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _tipoLegenda = value;
                                    _usarLegendaPadrao();
                                  });
                                }
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<TipoLegenda>(
                              title: const Text('Saida'),
                              subtitle: const Text('INCONFORMIDADE'),
                              value: TipoLegenda.inconformidade,
                              groupValue: _tipoLegenda,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() {
                                    _tipoLegenda = value;
                                    _usarLegendaPadrao();
                                  });
                                }
                              },
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                ...List.generate(_fields.length, (i) => _buildCard(i)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: addLegenda,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar item'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF000080),
                        side: const BorderSide(color: Color(0xFF00C896)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _usarLegendaPadrao,
                      icon: const Icon(Icons.restore),
                      label: const Text('Usar legenda padrão'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF000080),
                        side: const BorderSide(color: Color(0xFF00C896)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendaControllers {
  final valor = TextEditingController();
  final texto = TextEditingController();
  Color cor;

  _LegendaControllers({this.cor = Colors.red});

  void dispose() {
    valor.dispose();
    texto.dispose();
  }
}
