import 'package:flutter/material.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import '../app/globals.dart';
import '../models/dados.dart';
import '../models/imovel_data.dart';
import 'dados_imagem_preview.dart';
import 'drive_file_drag_data.dart';

/// Seção Imóvel com estado independente por instância.
class SecaoImovel extends StatefulWidget {
  const SecaoImovel({super.key});

  @override
  State<SecaoImovel> createState() => SecaoImovelState();
}

class SecaoImovelState extends State<SecaoImovel> {
  final _identificacaoController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _mobiliadoController = TextEditingController();
  final _quartosController = TextEditingController();
  final _banheirosController = TextEditingController();
  final _mapaUrlController = TextEditingController();

  MapaImagemFonte _mapaFonte = MapaImagemFonte.nenhuma;
  String? _mapaDriveFileId;
  String? _mapaDriveNome;
  String? _mapaDriveWebViewLink;
  String? _mapaDriveThumbnailLink;

  void carregarDados(ImovelData? dados) {
    if (dados == null) return;
    _identificacaoController.text = dados.protocolo;
    _enderecoController.text = dados.endereco;
    _mobiliadoController.text = dados.mobiliado;
    _quartosController.text = dados.quartos;
    _banheirosController.text = dados.banheiros;
    _mapaFonte = dados.mapaFonte;
    _mapaDriveFileId = dados.mapaDriveFileId;
    _mapaDriveNome = dados.mapaDriveNome;
    _mapaDriveWebViewLink = dados.mapaDriveWebViewLink;
    _mapaDriveThumbnailLink = dados.mapaDriveThumbnailLink;
    _mapaUrlController.text = dados.mapaPublicUrl ?? '';
    if (mounted) setState(() {});
  }

  ImovelData getDados() {
    return ImovelData(
      protocolo: _identificacaoController.text.trim(),
      endereco: _enderecoController.text.trim(),
      mobiliado: _mobiliadoController.text.trim(),
      quartos: _quartosController.text.trim(),
      banheiros: _banheirosController.text.trim(),
      mapaFonte: _mapaFonte,
      mapaPublicUrl: _mapaFonte == MapaImagemFonte.urlPublica ? _mapaUrlController.text.trim() : null,
      mapaDriveFileId: _mapaFonte == MapaImagemFonte.googleDrive ? _mapaDriveFileId : null,
      mapaDriveNome: _mapaFonte == MapaImagemFonte.googleDrive ? _mapaDriveNome : null,
      mapaDriveWebViewLink: _mapaFonte == MapaImagemFonte.googleDrive ? _mapaDriveWebViewLink : null,
      mapaDriveThumbnailLink: _mapaFonte == MapaImagemFonte.googleDrive ? _mapaDriveThumbnailLink : null,
    );
  }

  Future<void> _entrarGoogle() async {
    try {
      final acc = await appDriveService.signIn(context);
      if (acc == null) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Conta Google conectada.')),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha ao conectar: $e')),
        );
      }
    }
  }

  Future<void> _escolherMapaDrive() async {
    try {
      if (!await appDriveService.hasDriveAccess()) {
        await _entrarGoogle();
      }
      if (!await appDriveService.hasDriveAccess() || !mounted) return;
      openDrivePanelCallback?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arraste uma imagem do painel Google Drive para a área do mapa abaixo.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
    }
  }

  void _aplicarMapaDrive(drive.File f) {
    if (f.id == null) return;
    setState(() {
      _mapaFonte = MapaImagemFonte.googleDrive;
      _mapaDriveFileId = f.id;
      _mapaDriveNome = f.name;
      _mapaDriveWebViewLink = f.webViewLink;
      _mapaDriveThumbnailLink = f.thumbnailLink;
      _mapaUrlController.clear();
    });
  }

  void _usarUrlMapa() {
    final u = _mapaUrlController.text.trim();
    setState(() {
      if (u.isEmpty) {
        _mapaFonte = MapaImagemFonte.nenhuma;
        _mapaDriveFileId = null;
        _mapaDriveNome = null;
        _mapaDriveWebViewLink = null;
        _mapaDriveThumbnailLink = null;
      } else {
        _mapaFonte = MapaImagemFonte.urlPublica;
        _mapaDriveFileId = null;
        _mapaDriveNome = null;
        _mapaDriveWebViewLink = null;
        _mapaDriveThumbnailLink = null;
      }
    });
  }

  void _removerMapa() {
    setState(() {
      _mapaFonte = MapaImagemFonte.nenhuma;
      _mapaDriveFileId = null;
      _mapaDriveNome = null;
      _mapaDriveWebViewLink = null;
      _mapaDriveThumbnailLink = null;
      _mapaUrlController.clear();
    });
  }

  @override
  void dispose() {
    _identificacaoController.dispose();
    _enderecoController.dispose();
    _mobiliadoController.dispose();
    _quartosController.dispose();
    _banheirosController.dispose();
    _mapaUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = getDados();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _identificacaoController,
          decoration: const InputDecoration(
            labelText: 'Identificação',
            hintText: 'Ex: GARDENE7407',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.tag),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _enderecoController,
          decoration: const InputDecoration(
            labelText: 'Endereço',
            hintText: 'Ex: APARTAMENTO - RUA ISRAEL - 431 - BLOCO 7...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.location_on),
          ),
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _mobiliadoController,
          decoration: const InputDecoration(
            labelText: 'Mobiliado',
            hintText: 'Ex: SIM ou NÃO',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.chair),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _quartosController,
          decoration: const InputDecoration(
            labelText: 'Quartos',
            hintText: 'Ex: SUÍTE+2',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.bed),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _banheirosController,
          decoration: const InputDecoration(
            labelText: 'Banheiros',
            hintText: 'Ex: BANHEIRO SUÍTE +1',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.bathroom),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Mapa',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF000080),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _entrarGoogle,
              icon: const Icon(Icons.login, size: 18),
              label: const Text('Google'),
            ),
            OutlinedButton.icon(
              onPressed: _escolherMapaDrive,
              icon: const Icon(Icons.cloud_download, size: 18),
              label: const Text('Mapa no Drive'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _mapaUrlController,
          decoration: const InputDecoration(
            labelText: 'URL da imagem do mapa (opcional)',
            hintText: 'https://...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.link),
          ),
          onEditingComplete: _usarUrlMapa,
          onFieldSubmitted: (_) => _usarUrlMapa(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton(
              onPressed: _usarUrlMapa,
              child: const Text('Aplicar URL'),
            ),
            const SizedBox(width: 12),
            if (preview.temMapa)
              TextButton.icon(
                onPressed: _removerMapa,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remover mapa'),
              ),
          ],
        ),
        if (_mapaFonte == MapaImagemFonte.googleDrive && _mapaDriveNome != null) ...[
          const SizedBox(height: 8),
          Text(
            'Drive: $_mapaDriveNome',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
        ],
        const SizedBox(height: 12),
        DragTarget<DriveFileDragData>(
          onWillAcceptWithDetails: (_) => true,
          onAcceptWithDetails: (details) => _aplicarMapaDrive(details.data.file),
          builder: (context, candidate, rejected) {
            final active = candidate.isNotEmpty;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: 200,
              decoration: BoxDecoration(
                border: Border.all(
                  color: active ? const Color(0xFF00C896) : Colors.grey[400]!,
                  width: active ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child: preview.temMapa
                  ? (_mapaFonte == MapaImagemFonte.urlPublica
                      ? DadosImagemPreview(
                          img: DadosImagem(
                            fonte: ImagemFonte.urlPublica,
                            publicUrl: preview.mapaPublicUrl,
                            legenda: 'Mapa',
                          ),
                          width: double.infinity,
                          height: 200,
                        )
                      : _mapaFonte == MapaImagemFonte.googleDrive
                          ? DadosImagemPreview(
                              img: DadosImagem(
                                fonte: ImagemFonte.googleDrive,
                                driveFileId: preview.mapaDriveFileId,
                                driveWebViewLink: preview.mapaDriveWebViewLink,
                                driveThumbnailLink: preview.mapaDriveThumbnailLink,
                                legenda: 'Mapa',
                              ),
                              width: double.infinity,
                              height: 200,
                            )
                          : const SizedBox())
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Pré-visualização do mapa\n(arraste do painel Drive ou use a URL acima)',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    ),
            );
          },
        ),
      ],
    );
  }
}
