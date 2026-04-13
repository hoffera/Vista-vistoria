import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../app/globals.dart';
import '../models/dados.dart';
import '../models/legenda.dart';
import 'dados_imagem_preview.dart';
import 'drive_file_drag_data.dart';

/// Modo da seção: padrao (inconformidades, chaves), ambientes (com status e observação), medidores (com leitura e data), detalhado (com tópicos numerados, dados numerados, informações e legenda), imagens (apenas imagens com título e link).
enum ModoSecaoDados { padrao, ambientes, medidores, detalhado, imagens }

/// Seção genérica com subtópicos, itens e imagens.
/// Recebe titulo e icone por parâmetro para uso em INCONFORMIDADES, CHAVES, AMBIENTES, MEDIDORES.
class SecaoDados extends StatefulWidget {
  final String titulo;
  final IconData icone;
  /// Legenda padrão no diálogo ao adicionar imagem (ex: "Inconformidade", "Chave")
  final String legendaPadrao;
  /// Modo: ambientes (status+observação), medidores (leitura+data), padrao (inconformidades/chaves), detalhado (com tópicos numerados)
  final ModoSecaoDados modo;
  /// Lista de legendas disponíveis (para modo DETALHADO)
  final List<Legenda>? legendas;
  /// Força exibição dos campos Leitura e Data/hora (usado pelo pai quando modo é Medidores)
  final bool showCamposLeituraData;

  const SecaoDados({
    super.key,
    required this.titulo,
    required this.icone,
    this.legendaPadrao = 'Item',
    this.modo = ModoSecaoDados.padrao,
    this.legendas,
    this.showCamposLeituraData = false,
  });

  @override
  State<SecaoDados> createState() => SecaoDadosState();
}

class SecaoDadosState extends State<SecaoDados> {
  final List<_SubtopicoState> _subtopicos = [];

  Future<void> _driveOuAbrirPainel() async {
    if (!await appDriveService.hasDriveAccess()) {
      await appDriveService.signIn(context);
      if (!mounted) return;
      if (!await appDriveService.hasDriveAccess()) return;
    }
    openDrivePanelCallback?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Arraste imagens do painel Google Drive para a secção Imagens.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _aplicarDriveNoItem(
    _ItemState item,
    drive.File f,
    void Function(void Function()) setStateLike,
  ) {
    if (f.id == null) return;
    final legenda = item.descricaoController.text.trim().isEmpty
        ? widget.legendaPadrao
        : item.descricaoController.text.trim();
    setStateLike(() {
      item.adicionarImagem(
        DadosImagem(
          fonte: ImagemFonte.googleDrive,
          driveFileId: f.id,
          driveNome: f.name,
          driveWebViewLink: f.webViewLink,
          driveThumbnailLink: f.thumbnailLink,
          legenda: legenda,
          link: null,
        ),
      );
    });
  }

  void _aplicarDriveNoSubtopicoImagens(_SubtopicoState subtopico, drive.File f) {
    if (f.id == null) return;
    setState(() {
      subtopico.adicionarImagem(
        DadosImagem(
          fonte: ImagemFonte.googleDrive,
          driveFileId: f.id,
          driveNome: f.name,
          driveWebViewLink: f.webViewLink,
          driveThumbnailLink: f.thumbnailLink,
          legenda: widget.legendaPadrao,
          link: null,
        ),
      );
    });
  }

  /// Zona ampla para soltar ficheiros do Drive (substitui o quadradinho "+ Foto real").
  Widget _driveImagensDropArea({
    required Widget child,
    required void Function(drive.File f) onDrop,
  }) {
    return DragTarget<DriveFileDragData>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => onDrop(details.data.file),
      builder: (context, candidate, rejected) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: active ? const Color(0xFF00C896) : Colors.grey[400]!,
              width: active ? 2 : 1,
            ),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey[50],
          ),
          child: child,
        );
      },
    );
  }

  Widget _hintArrastarOuPainel({required VoidCallback onAbrirPainel}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAbrirPainel,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_upload_outlined, size: 32, color: Colors.grey[600]),
              const SizedBox(height: 8),
              Text(
                'Arraste imagens do painel Google Drive para esta secção',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Colors.grey[800]),
              ),
              const SizedBox(height: 4),
              Text(
                'Ou toque aqui para abrir o painel',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlocoImagensItem(_ItemState item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Imagens',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        _driveImagensDropArea(
          onDrop: (f) => _aplicarDriveNoItem(item, f, setState),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (item.imagens.isNotEmpty) ...[
                SizedBox(
                  height: 200,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: true,
                    padding: EdgeInsets.zero,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          final t = Curves.easeInOut.transform(animation.value);
                          return Transform.scale(
                            scale: 1.0 + 0.04 * t,
                            child: Material(
                              elevation: 6 * t,
                              borderRadius: BorderRadius.circular(8),
                              clipBehavior: Clip.antiAlias,
                              child: child,
                            ),
                          );
                        },
                        child: child,
                      );
                    },
                    itemCount: item.imagens.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() => item.reordenarImagem(oldIndex, newIndex));
                    },
                    itemBuilder: (context, index) {
                      final img = item.imagens[index];
                      final keyId = img.driveFileId ?? img.publicUrl ?? 'i$index';
                      return Padding(
                        key: ValueKey('it_${item.hashCode}_${keyId}_$index'),
                        padding: const EdgeInsets.only(right: 10),
                        child: SizedBox(
                          width: 112,
                          child: _buildImagemTile(item, index),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _hintArrastarOuPainel(onAbrirPainel: () => _adicionarImagem(item)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBlocoImagensModoImagens(_SubtopicoState subtopico) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Imagens',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        const SizedBox(height: 8),
        _driveImagensDropArea(
          onDrop: (f) => _aplicarDriveNoSubtopicoImagens(subtopico, f),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (subtopico.imagens.isNotEmpty) ...[
                SizedBox(
                  height: 240,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    buildDefaultDragHandles: true,
                    padding: EdgeInsets.zero,
                    proxyDecorator: (child, index, animation) {
                      return AnimatedBuilder(
                        animation: animation,
                        builder: (context, child) {
                          final t = Curves.easeInOut.transform(animation.value);
                          return Transform.scale(
                            scale: 1.0 + 0.04 * t,
                            child: Material(
                              elevation: 6 * t,
                              borderRadius: BorderRadius.circular(8),
                              clipBehavior: Clip.antiAlias,
                              child: child,
                            ),
                          );
                        },
                        child: child,
                      );
                    },
                    itemCount: subtopico.imagens.length,
                    onReorder: (oldIndex, newIndex) {
                      setState(() => subtopico.reordenarImagem(oldIndex, newIndex));
                    },
                    itemBuilder: (context, index) {
                      final img = subtopico.imagens[index];
                      final keyId = img.driveFileId ?? img.publicUrl ?? 's$index';
                      return Padding(
                        key: ValueKey('st_${subtopico.hashCode}_${keyId}_$index'),
                        padding: const EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 162,
                          child: _buildImagemTileImagens(subtopico, index),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _hintArrastarOuPainel(onAbrirPainel: () => _adicionarImagemImagens(subtopico)),
            ],
          ),
        ),
      ],
    );
  }

  void _adicionarSubtopico() {
    setState(() {
      final s = _SubtopicoState();
      // No modo detalhado, não criar item automaticamente
      if (widget.modo != ModoSecaoDados.detalhado) {
      s.adicionarItem();
      }
      _subtopicos.add(s);
    });
  }

  void _removerSubtopico(int index) {
    setState(() {
      _subtopicos[index].dispose();
      _subtopicos.removeAt(index);
    });
  }

  List<DadosSubtopico> getDados() {
    return _subtopicos.map((s) => s.toModel()).toList();
  }

  void carregarDados(List<DadosSubtopico> dados) {
    setState(() {
      // Limpar subtópicos existentes
      for (final s in _subtopicos) {
        s.dispose();
      }
      _subtopicos.clear();
      
      // Carregar dados salvos
      for (final dado in dados) {
        final s = _SubtopicoState();
        s.nomeController.text = dado.nome;
        
        // Carregar itens
        for (final itemData in dado.itens) {
          final item = _ItemState();
          item.descricaoController.text = itemData.descricao;
          item.statusController.text = itemData.status ?? '';
          item.observacaoController.text = itemData.observacao ?? '';
          item.leituraController.text = itemData.leitura ?? '';
          item.dataLeituraController.text = itemData.dataLeitura ?? '';
          item.legendaValorSelecionada = itemData.legendaValor;
          
          // Carregar informações adicionais
          for (final info in itemData.informacoes) {
            item.informacoesControllers.add((
              nome: TextEditingController(text: info.nome),
              valor: TextEditingController(text: info.valor),
            ));
          }
          
          // Carregar imagens
          item.imagens.addAll(itemData.imagens);
          
          s.itens.add(item);
        }
        
        // Carregar imagens do subtópico (modo detalhado)
        if (dado.imagens.isNotEmpty) {
          s.imagens.addAll(dado.imagens);
        }
        
        _subtopicos.add(s);
      }
      
      // Para modo imagens, garantir que há pelo menos um subtópico
      if (widget.modo == ModoSecaoDados.imagens && _subtopicos.isEmpty) {
        _subtopicos.add(_SubtopicoState());
      }
    });
  }

  static const _statusValidos = ['NOVO', 'BOM', 'REGULAR', 'NÃO TESTADO', 'RUIM'];
  bool _statusValido(String v) => v.isNotEmpty && _statusValidos.contains(v);

  @override
  void dispose() {
    for (final s in _subtopicos) {
      s.dispose();
    }
    super.dispose();
  }

  String get _hintSubtopicos => switch (widget.modo) {
        ModoSecaoDados.ambientes => 'Ambientes (ex: sala/cozinha, quarto, banheiro). Cada item tem status (NOVO/BOM/REGULAR/NÃO TESTADO/RUIM) e observação.',
        ModoSecaoDados.medidores => 'Medidores (ex: Gas, Energia). Cada item tem leitura e data. Adicione fotos.',
        ModoSecaoDados.padrao => 'Subtópicos (ex: SALA, COZINHA). Cada subtópico tem ao menos 1 item. Adicione fotos reais, legenda e link do vídeo.',
        ModoSecaoDados.detalhado => 'Tópicos numerados (ex: 1. Cozinha, 2. Quarto). Arraste do painel Drive para a caixa Imagens; reordene pela alça à direita de cada miniatura.',
        ModoSecaoDados.imagens => 'Adicione imagens com título e link para vídeo (opcional).',
      };

  @override
  Widget build(BuildContext context) {
    // Modo imagens: UI simplificada apenas com imagens
    if (widget.modo == ModoSecaoDados.imagens) {
      // Usar o primeiro subtópico (ou criar um vazio) para armazenar as imagens
      if (_subtopicos.isEmpty) {
        _subtopicos.add(_SubtopicoState());
      }
      final subtopico = _subtopicos[0];
      
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _hintSubtopicos,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 12),
          _buildBlocoImagensModoImagens(subtopico),
        ],
      );
    }
    
    // Modos normais: UI com subtópicos
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _hintSubtopicos,
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 12),
        ...List.generate(_subtopicos.length, (i) => _buildSubtopicoCard(i)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _adicionarSubtopico,
          icon: const Icon(Icons.add),
          label: const Text('Adicionar subtópico'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF000080),
            side: const BorderSide(color: Color(0xFF00C896)),
          ),
        ),
      ],
    );
  }

  Widget _buildSubtopicoCard(int index) {
    final s = _subtopicos[index];
    final isDetalhado = widget.modo == ModoSecaoDados.detalhado;
    final isMedidores = widget.showCamposLeituraData ||
        widget.modo == ModoSecaoDados.medidores;
    return Card(
      key: ValueKey('${widget.titulo}_subtopico_$index'),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Medidores: sem campo "Tipo do medidor" — apenas botão remover grupo
            if (!isMedidores) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (isDetalhado)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(
                        '${index + 1}.',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF000080)),
                      ),
                    ),
                  Expanded(
                    child: TextField(
                      controller: s.nomeController,
                      decoration: InputDecoration(
                        labelText: widget.modo == ModoSecaoDados.ambientes
                            ? 'Ambiente (ex: sala/cozinha, quarto)'
                            : isDetalhado
                                ? 'Tópico (ex: Cozinha, Quarto)'
                                : 'Subtópico (ex: SALA, COZINHA, SUÍTE)',
                        hintText: isDetalhado ? 'Cozinha' : 'SALA',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _removerSubtopico(index),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    tooltip: 'Remover subtópico',
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ] else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _subtopicos.length <= 1 ? null : () => _removerSubtopico(index),
                    icon: const Icon(Icons.remove_circle_outline, size: 20),
                    color: Colors.red,
                    tooltip: 'Remover grupo',
                  ),
                ],
              ),
            ],
            ...List.generate(s.itens.length, (i) => _buildItemCard(subtopico: s, itemIndex: i, topicoIndex: index)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                s.adicionarItem();
                setState(() {});
              },
              icon: const Icon(Icons.add_circle_outline, size: 18),
              label: Text(isDetalhado ? 'Adicionar dado' : 'Adicionar item'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF000080),
                side: const BorderSide(color: Color(0xFF00C896)),
                padding: const EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard({required _SubtopicoState subtopico, required int itemIndex, int? topicoIndex}) {
    final item = subtopico.itens[itemIndex];
    final isDetalhado = widget.modo == ModoSecaoDados.detalhado;
    // Exibir Leitura/Data: parâmetro do pai, modo medidores ou título com "MEDIDOR"
    final isMedidores = widget.showCamposLeituraData ||
        widget.modo == ModoSecaoDados.medidores ||
        widget.titulo.toUpperCase().contains('MEDIDOR');
    return Card(
      key: ValueKey('${widget.titulo}_item_${subtopico.hashCode}_$itemIndex'),
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDetalhado && topicoIndex != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 12),
                    child: Text(
                      '${topicoIndex + 1}.${itemIndex + 1}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF000080)),
                    ),
                  ),
                Expanded(
                  child: isDetalhado
                      ? TextField(
                          controller: item.descricaoController,
                          decoration: const InputDecoration(
                            labelText: 'Nome do dado',
                            hintText: 'Ex: porta, piso, parede',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        )
                      : TextField(
                          controller: item.descricaoController,
                          decoration: InputDecoration(
                            labelText: widget.modo == ModoSecaoDados.medidores 
                                ? 'Identificação do medidor (opcional)' 
                                : 'Descrição do item',
                            hintText: widget.modo == ModoSecaoDados.medidores 
                                ? 'Ex: nº 0782543' 
                                : 'Ex: Cadeiras quebradas na parte superior',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                ),
                if (widget.modo == ModoSecaoDados.ambientes)
                  SizedBox(
                    width: 140,
                    child: DropdownButtonFormField<String?>(
                      value: _statusValido(item.statusController.text) ? item.statusController.text : null,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem<String?>(value: null, child: Text('Selecione')),
                        DropdownMenuItem(value: 'NOVO', child: Text('NOVO')),
                        DropdownMenuItem(value: 'BOM', child: Text('BOM')),
                        DropdownMenuItem(value: 'REGULAR', child: Text('REGULAR')),
                        DropdownMenuItem(value: 'NÃO TESTADO', child: Text('NÃO TESTADO')),
                        DropdownMenuItem(value: 'RUIM', child: Text('RUIM')),
                      ],
                      onChanged: (v) {
                        item.statusController.text = v ?? '';
                        setState(() {});
                      },
                    ),
                  ),
                IconButton(
                  onPressed: subtopico.itens.length <= 1
                      ? null
                      : () {
                          subtopico.removerItem(itemIndex);
                          setState(() {});
                        },
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: Colors.red,
                  tooltip: 'Remover item',
                ),
              ],
            ),
            // Medidores: somente Identificação, Leitura e Imagens
            if (isMedidores) ...[
              const SizedBox(height: 12),
              TextField(
                controller: item.leituraController,
                decoration: const InputDecoration(
                  labelText: 'Leitura',
                  hintText: 'Ex: 161059 m3',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (widget.modo == ModoSecaoDados.ambientes) ...[
              const SizedBox(height: 8),
              TextField(
                controller: item.observacaoController,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Ex: Manchas e oxidação',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
            if (isDetalhado) ...[
              const SizedBox(height: 12),
              if (widget.legendas != null && widget.legendas!.isNotEmpty) ...[
                DropdownButtonFormField<String?>(
                  value: item.legendaValorSelecionada,
                  decoration: const InputDecoration(
                    labelText: 'Legenda (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
                    ...widget.legendas!.map((leg) => DropdownMenuItem<String?>(
                          value: leg.valor,
                          child: Row(
                            children: [
                              Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: leg.cor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(leg.valor),
                            ],
                          ),
                        )),
                  ],
                  onChanged: (v) {
                    setState(() {
                      item.legendaValorSelecionada = v;
                    });
                  },
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Informações adicionais',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              ...List.generate(item.informacoesControllers.length, (i) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: item.informacoesControllers[i].nome,
                          decoration: InputDecoration(
                            labelText: 'Nome ${i + 1}',
                            hintText: 'Ex: Marca',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: item.informacoesControllers[i].valor,
                          decoration: InputDecoration(
                            labelText: 'Valor ${i + 1}',
                            hintText: 'Ex: Midea',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          item.removerInformacao(i);
                          setState(() {});
                        },
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        color: Colors.red,
                        tooltip: 'Remover',
                      ),
                    ],
                  ),
                );
              }),
              OutlinedButton.icon(
                onPressed: () {
                  item.adicionarInformacao();
                  setState(() {});
                },
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Adicionar informação'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF000080),
                  side: const BorderSide(color: Color(0xFF00C896)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
              const SizedBox(height: 16),
              _buildBlocoImagensItem(item),
            ],
            if (!isDetalhado) ...[
            const SizedBox(height: 12),
            _buildBlocoImagensItem(item),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildImagemTile(_ItemState item, int imgIndex) {
    final img = item.imagens[imgIndex];
    return SizedBox(
      width: 100,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 100,
            height: 80,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
            child: DadosImagemPreview(img: img, width: 100, height: 80),
            ),
          ),
          const SizedBox(height: 4),
          Text(img.legenda, style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (img.link != null && img.link!.isNotEmpty)
            Text(img.link!, style: TextStyle(fontSize: 9, color: Colors.blue[700]), maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _editarImagem(item, imgIndex),
                icon: const Icon(Icons.edit, size: 16),
                tooltip: 'Editar legenda/link',
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  item.removerImagem(imgIndex);
                  setState(() {});
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                color: Colors.red,
                tooltip: 'Remover',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _adicionarImagem(_ItemState item) async {
    try {
      await _driveOuAbrirPainel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar imagem: $e')),
        );
      }
    }
  }

  Future<(String, String)?> _mostrarDialogLegendaLink({
    required String legendaInicial,
    String linkInicial = '',
  }) async {
    final legendaController = TextEditingController(text: legendaInicial);
    final linkController = TextEditingController(text: linkInicial);
    final salvou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Legenda e link da imagem'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: legendaController,
                decoration: const InputDecoration(
                  labelText: 'Legenda',
                  hintText: 'Ex: Item',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: linkController,
                decoration: const InputDecoration(
                  labelText: 'Link do vídeo (opcional)',
                  hintText: 'https://...',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    final legenda = legendaController.text.trim().isEmpty ? widget.legendaPadrao : legendaController.text.trim();
    final link = linkController.text.trim();
    legendaController.dispose();
    linkController.dispose();
    return salvou == true ? (legenda, link) : null;
  }

  Future<void> _editarImagem(_ItemState item, int imgIndex) async {
    final img = item.imagens[imgIndex];
    final legendaLink = await _mostrarDialogLegendaLink(
      legendaInicial: img.legenda,
      linkInicial: img.link ?? '',
    );
    if (legendaLink == null || !mounted) return;

    setState(() {
      item.atualizarImagem(
        imgIndex,
        DadosImagem(
          fonte: img.fonte,
          publicUrl: img.publicUrl,
          driveFileId: img.driveFileId,
          driveNome: img.driveNome,
          driveWebViewLink: img.driveWebViewLink,
          driveThumbnailLink: img.driveThumbnailLink,
          legenda: legendaLink.$1,
          link: legendaLink.$2.isEmpty ? null : legendaLink.$2,
        ),
      );
    });
  }

  // Métodos específicos para modo IMAGENS
  Widget _buildImagemTileImagens(_SubtopicoState subtopico, int imgIndex) {
    final img = subtopico.imagens[imgIndex];
    return SizedBox(
      width: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
              width: 150,
              height: 120,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(4),
              ),
              child: DadosImagemPreview(img: img, width: 150, height: 120),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            img.legenda,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (img.link != null && img.link!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                img.link!,
                style: TextStyle(fontSize: 10, color: Colors.blue[700]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          Row(
            children: [
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => _editarImagemImagens(subtopico, imgIndex),
                icon: const Icon(Icons.edit, size: 18),
                tooltip: 'Editar título/link',
              ),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () {
                  subtopico.removerImagem(imgIndex);
                  setState(() {});
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                color: Colors.red,
                tooltip: 'Remover',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _adicionarImagemImagens(_SubtopicoState subtopico) async {
    try {
      await _driveOuAbrirPainel();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar imagem: $e')),
        );
      }
    }
  }

  Future<void> _editarImagemImagens(_SubtopicoState subtopico, int imgIndex) async {
    final img = subtopico.imagens[imgIndex];
    final legendaLink = await _mostrarDialogLegendaLink(
      legendaInicial: img.legenda,
      linkInicial: img.link ?? '',
    );
    if (legendaLink == null || !mounted) return;

    setState(() {
      subtopico.atualizarImagem(
        imgIndex,
        DadosImagem(
          fonte: img.fonte,
          publicUrl: img.publicUrl,
          driveFileId: img.driveFileId,
          driveNome: img.driveNome,
          driveWebViewLink: img.driveWebViewLink,
          driveThumbnailLink: img.driveThumbnailLink,
          legenda: legendaLink.$1,
          link: legendaLink.$2.isEmpty ? null : legendaLink.$2,
        ),
      );
    });
  }
}

class _SubtopicoState {
  final nomeController = TextEditingController();
  final List<_ItemState> itens = [];
  // Para modo DETALHADO: imagens no nível do tópico
  final List<DadosImagem> imagens = [];

  void adicionarItem() {
    itens.add(_ItemState());
  }

  void removerItem(int index) {
    if (itens.length <= 1) return;
    itens[index].dispose();
    itens.removeAt(index);
  }

  void adicionarImagem(DadosImagem img) {
    imagens.add(img);
  }

  void removerImagem(int index) {
    imagens.removeAt(index);
  }

  void atualizarImagem(int index, DadosImagem nova) {
    imagens[index] = nova;
  }

  void reordenarImagem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= imagens.length) return;
    if (newIndex < 0 || newIndex > imagens.length) return;
    if (newIndex > oldIndex) newIndex--;
    final x = imagens.removeAt(oldIndex);
    imagens.insert(newIndex, x);
  }

  DadosSubtopico toModel() {
    final itensModel = itens.map((i) => i.toModel()).toList();
    return DadosSubtopico(
      nome: nomeController.text.trim(),
      itens: itensModel,
      imagens: imagens.isNotEmpty ? List.from(imagens) : null,
    );
  }

  void dispose() {
    nomeController.dispose();
    for (final i in itens) {
      i.dispose();
    }
  }
}

class _ItemState {
  final descricaoController = TextEditingController();
  final statusController = TextEditingController();
  final observacaoController = TextEditingController();
  final leituraController = TextEditingController();
  final dataLeituraController = TextEditingController();
  // Para modo DETALHADO: lista de informações (nome e valor) e legenda selecionada
  final List<({TextEditingController nome, TextEditingController valor})> informacoesControllers = [];
  String? legendaValorSelecionada;

  void adicionarImagem(DadosImagem img) {
    imagens.add(img);
  }

  void removerImagem(int index) {
    imagens.removeAt(index);
  }

  void atualizarImagem(int index, DadosImagem nova) {
    imagens[index] = nova;
  }

  void reordenarImagem(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= imagens.length) return;
    if (newIndex < 0 || newIndex > imagens.length) return;
    if (newIndex > oldIndex) newIndex--;
    final x = imagens.removeAt(oldIndex);
    imagens.insert(newIndex, x);
  }

  void adicionarInformacao() {
    informacoesControllers.add((
      nome: TextEditingController(),
      valor: TextEditingController(),
    ));
  }

  void removerInformacao(int index) {
    informacoesControllers[index].nome.dispose();
    informacoesControllers[index].valor.dispose();
    informacoesControllers.removeAt(index);
  }

  final List<DadosImagem> imagens = [];

  DadosItem toModel() {
    return DadosItem(
      descricao: descricaoController.text.trim(),
      imagens: List.from(imagens),
      status: statusController.text.trim().isEmpty ? null : statusController.text.trim(),
      observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
      leitura: leituraController.text.trim().isEmpty ? null : leituraController.text.trim(),
      dataLeitura: dataLeituraController.text.trim().isEmpty ? null : dataLeituraController.text.trim(),
      informacoes: informacoesControllers
          .map((c) => (
                nome: c.nome.text.trim(),
                valor: c.valor.text.trim(),
              ))
          .where((t) => t.nome.isNotEmpty && t.valor.isNotEmpty)
          .map((t) => InformacaoAdicional(nome: t.nome, valor: t.valor))
          .toList(),
      legendaValor: legendaValorSelecionada,
    );
  }

  void dispose() {
    descricaoController.dispose();
    statusController.dispose();
    observacaoController.dispose();
    leituraController.dispose();
    dataLeituraController.dispose();
    for (final c in informacoesControllers) {
      c.nome.dispose();
      c.valor.dispose();
    }
  }
}
