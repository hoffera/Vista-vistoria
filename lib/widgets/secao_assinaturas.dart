import 'package:flutter/material.dart';

import '../models/assinatura.dart';

/// Seção de assinaturas: máximo 2 por linha no PDF.
/// Cada assinatura tem título e subtítulo.
class SecaoAssinaturas extends StatefulWidget {
  const SecaoAssinaturas({super.key});

  @override
  State<SecaoAssinaturas> createState() => SecaoAssinaturasState();
}

class SecaoAssinaturasState extends State<SecaoAssinaturas> {
  final List<_AssinaturaState> _assinaturas = [];

  void _adicionarAssinatura() {
    setState(() {
      _assinaturas.add(_AssinaturaState());
    });
  }

  void _removerAssinatura(int index) {
    setState(() {
      _assinaturas[index].dispose();
      _assinaturas.removeAt(index);
    });
  }

  List<Assinatura> getAssinaturas() {
    return _assinaturas
        .map((a) => Assinatura(
              titulo: a.tituloController.text.trim(),
              subtitulo: a.subtituloController.text.trim(),
            ))
        .where((a) => a.titulo.isNotEmpty || a.subtitulo.isNotEmpty)
        .toList();
  }

  void carregarAssinaturas(List<Assinatura> assinaturas) {
    setState(() {
      // Limpar assinaturas existentes
      for (final a in _assinaturas) {
        a.dispose();
      }
      _assinaturas.clear();
      
      // Carregar assinaturas salvas
      for (final assinatura in assinaturas) {
        final a = _AssinaturaState();
        a.tituloController.text = assinatura.titulo;
        a.subtituloController.text = assinatura.subtitulo;
        _assinaturas.add(a);
      }
    });
  }

  @override
  void dispose() {
    for (final a in _assinaturas) {
      a.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Máximo 2 assinaturas por linha no PDF. Cada assinatura tem título e subtítulo.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 16,
          runSpacing: 12,
          children: List.generate(_assinaturas.length, (i) => _buildAssinaturaCard(i)),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _adicionarAssinatura,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar assinatura'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF000080),
            side: const BorderSide(color: Color(0xFF00C896)),
          ),
        ),
      ],
    );
  }

  Widget _buildAssinaturaCard(int index) {
    final a = _assinaturas[index];
    return SizedBox(
      width: 280,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Assinatura ${index + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF000080),
                      fontSize: 12,
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    onPressed: () => _removerAssinatura(index),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: Colors.red,
                    tooltip: 'Remover assinatura',
                  ),
                ],
              ),
              TextField(
                controller: a.tituloController,
                decoration: const InputDecoration(
                  labelText: 'Título',
                  hintText: 'Ex: GM7 ASSESSORIA IMOBILIÁRIA LTDA',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: a.subtituloController,
                decoration: const InputDecoration(
                  labelText: 'Subtítulo',
                  hintText: 'Ex: ADMINISTRADOR',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssinaturaState {
  final tituloController = TextEditingController();
  final subtituloController = TextEditingController();

  void dispose() {
    tituloController.dispose();
    subtituloController.dispose();
  }
}
