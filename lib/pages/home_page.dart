import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_iconpicker/Models/configuration.dart';
import 'package:flutter_iconpicker/flutter_iconpicker.dart';
import 'package:screenshot/screenshot.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:vistoria_pdf/utils/colors.dart';
import 'package:vistoria_pdf/utils/pdf_open_new_tab.dart';

import '../models/assinatura.dart';
import '../models/dados.dart';
import '../models/imovel_data.dart';
import '../models/legenda.dart';
import '../models/observacao_item.dart';
import '../models/pessoa.dart';
import '../models/vistoria.dart';
import '../models/vistoria_salva.dart';
import '../app/globals.dart';
import '../services/pdf_image_resolver.dart';
import '../services/pdf_service.dart';
import '../services/user_preferences_service.dart';
import '../services/vistoria_document_service.dart';
import '../widgets/drive_image_picker_sheet.dart';
import '../widgets/secao_assinaturas.dart';
import '../widgets/secao_dados.dart';
import '../widgets/secao_imovel.dart';
import '../widgets/secao_legendas.dart';
import '../widgets/secao_observacoes.dart';

class HomePage extends StatefulWidget {
  final VistoriaData? vistoriaData;
  /// Caminho absoluto do documento .json (desktop/mobile) quando aberto a partir do disco.
  final String? vistoriaArquivoPath;
  final String? tipoInicial; // Tipo inicial da vistoria (ENTRADA ou SAÍDA)

  const HomePage({super.key, this.vistoriaData, this.vistoriaArquivoPath, this.tipoInicial});

  @override
  State<HomePage> createState() => _HomePageState();
}

// Intent para o atalho de atualizar preview
class _AtualizarPreviewIntent extends Intent {
  const _AtualizarPreviewIntent();
}

class _PessoaControllers {
  final nome = TextEditingController();
  final cpfCnpj = TextEditingController();
  final funcao = TextEditingController();

  void dispose() {
    nome.dispose();
    cpfCnpj.dispose();
    funcao.dispose();
  }
}

// Widget de item do menu simples
class _TimelineItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final bool temConteudo;
  final bool isLast;
  final VoidCallback onTap;

  const _TimelineItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.temConteudo,
    required this.isLast,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF00C896).withOpacity(0.1) : null,
          border: isSelected
              ? Border(
                  left: BorderSide(
                    color: const Color(0xFF00C896),
                    width: 3,
                  ),
                )
              : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? const Color(0xFF00C896)
                  : Colors.grey[600],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected
                      ? const Color(0xFF00C896)
                      : Colors.grey[700],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomePageState extends State<HomePage> {
  final _formKey = GlobalKey<FormState>();
  final _nomeVistoriaController = TextEditingController();
  final _numeroVistoriaController = TextEditingController();
  final _dataController = TextEditingController();
  final _vistoriadorController = TextEditingController();
  late final TextEditingController _tipoController;
  final _introducaoController = TextEditingController();
  final _observacaoComplementarController = TextEditingController();

  final List<_PessoaControllers> _pessoasFields = [];
  final _secaoLegendasKey = GlobalKey<SecaoLegendasState>();
  final _secaoObservacoesKey = GlobalKey<SecaoObservacoesState>();

  /// Keys e cache por instanceId para seções duplicáveis (1, 5, 6, 7, 8, 9).
  /// Cada instância tem seu próprio estado e dados.
  final Map<String, GlobalKey<SecaoImovelState>> _secaoImovelKeys = {};
  final Map<String, GlobalKey<SecaoDadosState>> _secaoDadosKeys = {};
  final Map<String, GlobalKey<SecaoAssinaturasState>> _secaoAssinaturasKeys = {};
  final Map<String, ImovelData> _imovelCache = {};
  final Map<String, List<DadosSubtopico>> _dadosCache = {};
  final Map<String, List<Assinatura>> _assinaturasCache = {};
  int _instanceCounter = 0;

  /// Cache para legendas e observações (seções compartilhadas).
  List<Legenda> _legendasCache = [];
  List<ObservacaoItem> _itensObservacaoCache = [];

  Uint8List? _pdfBytes;
  bool _isLoadingPreview = false;
  String? _previewError;
  int _previewVersion = 0;
  final PdfViewerController _pdfViewerController = PdfViewerController();

  /// Caminho do .json após guardar ou ao abrir ficheiro (desktop/mobile).
  String? _caminhoArquivoAtual;
  /// Web: após o primeiro guardar nesta sessão, não voltar a pedir nome no diálogo.
  bool _documentoJaSalvoWeb = false;

  bool _drivePanelOpen = false;

  Future<void> _openDrivePanel() async {
    if (!await appDriveService.hasDriveAccess()) {
      await appDriveService.signIn(context);
      if (!await appDriveService.hasDriveAccess()) return;
    }
    if (mounted) setState(() => _drivePanelOpen = true);
  }

  void _closeDrivePanel() {
    if (mounted) setState(() => _drivePanelOpen = false);
  }

  /// Ordem das seções no menu. Cada item tem instanceId único (para 5,6,7,8,9) ou vazio (0,1,2,3,4).
  List<({String instanceId, int sectionId})> _ordemSecoes = [(instanceId: '', sectionId: 0)];

  /// Índice selecionado dentro de _ordemSecoes (qual item da lista está ativo).
  int _secaoSelecionada = 0;

  /// Chave composta: sectionId + instanceId garante isolamento entre seções do mesmo tipo.
  String _makeKey(int sectionId, String instanceId) => '${sectionId}_$instanceId';

  /// Cria e retorna uma GlobalKey para SecaoImovel da instância.
  GlobalKey<SecaoImovelState> _obterKeySecaoImovel(String instanceId) {
    final k = _makeKey(1, instanceId);
    return _secaoImovelKeys.putIfAbsent(k, () => GlobalKey<SecaoImovelState>());
  }

  /// Cria e retorna uma GlobalKey para SecaoDados da instância.
  GlobalKey<SecaoDadosState> _obterKeySecaoDados(int sectionId, String instanceId) {
    final k = _makeKey(sectionId, instanceId);
    return _secaoDadosKeys.putIfAbsent(k, () => GlobalKey<SecaoDadosState>());
  }

  /// Cria e retorna uma GlobalKey para SecaoAssinaturas da instância.
  GlobalKey<SecaoAssinaturasState> _obterKeySecaoAssinaturas(String instanceId) {
    final k = _makeKey(9, instanceId);
    return _secaoAssinaturasKeys.putIfAbsent(k, () => GlobalKey<SecaoAssinaturasState>());
  }

  /// Obtém dados do Imóvel (seção 1) para a instância.
  ImovelData _getImovelForInstance(String instanceId) {
    if (instanceId.isEmpty) return const ImovelData();
    final k = _makeKey(1, instanceId);
    final key = _secaoImovelKeys[k];
    final dados = key?.currentState?.getDados();
    if (dados != null) {
      _imovelCache[k] = dados;
      return dados;
    }
    return _imovelCache[k] ?? const ImovelData();
  }

  /// Obtém dados da seção de dados (5) para a instância.
  List<DadosSubtopico> _getDadosForInstance(String instanceId) {
    if (instanceId.isEmpty) return [];
    final k = _makeKey(5, instanceId);
    final key = _secaoDadosKeys[k];
    final dados = key?.currentState?.getDados();
    if (dados != null) {
      _dadosCache[k] = dados;
      return dados;
    }
    return _dadosCache[k] ?? [];
  }

  /// Obtém assinaturas da seção 9 para a instância.
  List<Assinatura> _getAssinaturasForInstance(String instanceId) {
    if (instanceId.isEmpty) return [];
    final k = _makeKey(9, instanceId);
    final key = _secaoAssinaturasKeys[k];
    final assinaturas = key?.currentState?.getAssinaturas();
    if (assinaturas != null) {
      _assinaturasCache[k] = assinaturas;
      return assinaturas;
    }
    return _assinaturasCache[k] ?? [];
  }

  /// Seções 1, 5, 9 podem ser duplicadas; cada cópia tem estado independente.
  bool _isSecaoDuplicavel(int sectionId) =>
      sectionId == 1 || sectionId == 5 || sectionId == 9;

  /// Verifica se uma seção tem conteúdo preenchido
  bool _verificarSeTemConteudo(({String instanceId, int sectionId}) entry) {
    switch (entry.sectionId) {
      case 0:
        return _dataController.text.isNotEmpty ||
            _vistoriadorController.text.isNotEmpty ||
            _tipoController.text.isNotEmpty;
      case 1:
        final imovel = _getImovelForInstance(entry.instanceId);
        return imovel.protocolo.isNotEmpty || imovel.endereco.isNotEmpty;
      case 2:
        return _introducaoController.text.isNotEmpty ||
            _legendasCache.isNotEmpty ||
            _itensObservacaoCache.isNotEmpty ||
            _observacaoComplementarController.text.isNotEmpty;
      case 3:
        return _pessoasFields.any((p) =>
            p.nome.text.isNotEmpty ||
            p.cpfCnpj.text.isNotEmpty ||
            p.funcao.text.isNotEmpty);
      case 4:
        return _itensObservacaoCache.isNotEmpty;
      case 5:
        final dados = _getDadosForInstance(entry.instanceId);
        return dados.isNotEmpty;
      case 9:
        final assinaturas = _getAssinaturasForInstance(entry.instanceId);
        return assinaturas.isNotEmpty;
      default:
        return false;
    }
  }

  /// Antes de trocar a seção selecionada, cacheia os dados da seção atual (para instâncias desmontadas).
  void _cacheSecaoAtual() {
    if (_secaoSelecionada >= _ordemSecoes.length) return;
    final entry = _ordemSecoes[_secaoSelecionada];
    if (!_isSecaoDuplicavel(entry.sectionId) || entry.instanceId.isEmpty) return;
    final k = _makeKey(entry.sectionId, entry.instanceId);
    if (entry.sectionId == 1) {
      final key = _secaoImovelKeys[k];
      final d = key?.currentState?.getDados();
      if (d != null) _imovelCache[k] = d;
    } else if (entry.sectionId == 9) {
      final key = _secaoAssinaturasKeys[k];
      final a = key?.currentState?.getAssinaturas();
      if (a != null) _assinaturasCache[k] = a;
    } else {
      final key = _secaoDadosKeys[k];
      final d = key?.currentState?.getDados();
      if (d != null) _dadosCache[k] = d;
    }
  }

  /// Cacheia os dados de todas as seções (útil antes de gerar o PDF)
  void _cachearTodasSecoes() {
    for (final entry in _ordemSecoes) {
      if (!_isSecaoDuplicavel(entry.sectionId) || entry.instanceId.isEmpty) continue;
      final k = _makeKey(entry.sectionId, entry.instanceId);
      if (entry.sectionId == 1) {
        final key = _secaoImovelKeys[k];
        final d = key?.currentState?.getDados();
        if (d != null) _imovelCache[k] = d;
      } else if (entry.sectionId == 9) {
        final key = _secaoAssinaturasKeys[k];
        final a = key?.currentState?.getAssinaturas();
        if (a != null) _assinaturasCache[k] = a;
      } else if (entry.sectionId == 5) {
        final key = _secaoDadosKeys[k];
        final d = key?.currentState?.getDados();
        if (d != null) _dadosCache[k] = d;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _caminhoArquivoAtual = widget.vistoriaArquivoPath;
    // Inicializar tipo controller com tipo inicial ou padrão
    final tipoInicial = widget.tipoInicial ?? 'SAÍDA';
    _tipoController = TextEditingController(text: tipoInicial);
    
    // Configurar texto de introdução e observação complementar baseado no tipo
    if (widget.vistoriaData == null) {
      // Preencher data atual automaticamente
      final agora = DateTime.now();
      _dataController.text = '${agora.day.toString().padLeft(2, '0')}/${agora.month.toString().padLeft(2, '0')}/${agora.year}';
      
      // Carregar vistoriador padrão salvo (async)
      _carregarVistoriadorPadrao().then((_) {
        // Gerar nome sugerido automaticamente após carregar vistoriador
        if (mounted) {
          _nomeVistoriaController.text = 'Vistoria $tipoInicial - ${_dataController.text}';
        }
      });
      
      if (tipoInicial == 'ENTRADA') {
        _introducaoController.text = 'Vistoria imobiliária profissional terceirizada, realizada com o objetivo de registrar o estado de conservação do imóvel e de todos os itens que o compõem no momento de sua desocupação. Prazo de contestação de 7 dias caso o mesmo já não esteja estipulado em contrato, para se manifestar expressamente sobre a vistoria apresentada. Fluído esse prazo, sem manifestação expressa por parte do Locatário, subentende-se aceita a vistoria na sua integralidade.Para contestação ou complementação entrar em contato no Whatsapp (47) 98911-0543.';
        _observacaoComplementarController.text = 'Testes elétricos e hidráulicos realizados para registrar os funcionamentos iniciais dos itens, ciclos rápidos, e funções de ligar/desligar; deve se levar em consideração que após estas verificações in loco em função de utilização continua, ou em função do tempo de uso do item, e também as manutenções preventivas e de rotinas que são realizadas ou não no imóvel e itens do mesmo, poderá ocorrer mal funcionamento ou parada de funcionamento, e neste caso havendo alguma ocorrência a Vista não se responsabiliza por manutenções que tenham que ser realizadas.\n\nPermanecemos à disposição para esclarecimentos e eventuais dúvidas: vistasuavistoria@gmail.com';
      } else {
        // Texto padrão para SAÍDA
        _introducaoController.text = 'Vistoria imobiliária profissional terceirizada, realizada com o objetivo de registrar o estado de conservação do imóvel e de todos os itens que o compõem no momento de sua desocupação. O presente relatório descreve as inconformidades do imóvel em relação à vistoria de entrada. Consideram-se inconformidades todas as diferenças identificadas, sejam elas  positivas (melhorias) ou negativas (avarias), excetuando-se aquelas decorrentes do uso normal e da ação do tempo, conforme disposto na Lei nº 8.245/91 (Lei do Inquilinato), Art. 23, inciso III. Fica sob responsabilidade das partes a negociação e definição quanto à execução dos reparos, manutenções, limpeza, pintura, substituições e demais serviços que se fizerem necessários.';
        _observacaoComplementarController.text = 'Nos casos em que o imóvel ainda se encontra ocupado pelos locatários, o que pode dificultar a execução do procedimento padrão de vistoria, a Vista não se responsabiliza por danos, alterações ou intervenções realizadas no imóvel após a data da vistoria.';
      }
    }
    
    _adicionarPessoa();
    
    // Gerar número automático se não estiver editando
    if (widget.vistoriaData == null) {
      _gerarNumeroAutomatico();
      
      // Criar estrutura pré-definida baseada no tipo
      if (tipoInicial == 'ENTRADA') {
        _criarEstruturaVistoriaEntrada();
      } else if (tipoInicial == 'SAÍDA') {
        _criarEstruturaVistoriaSaida();
      }
    }
    
    if (widget.vistoriaData != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carregarVistoriaData(widget.vistoriaData!);
      });
    }

    openDrivePanelCallback = () {
      unawaited(_openDrivePanel());
    };
  }

  Future<void> _carregarVistoriadorPadrao() async {
    final vistoriadorPadrao = await UserPreferencesService.obterVistoriadorPadrao();
    if (vistoriadorPadrao != null && vistoriadorPadrao.isNotEmpty) {
      _vistoriadorController.text = vistoriadorPadrao;
    } else {
      // Valor padrão se não houver salvo
      _vistoriadorController.text = 'MARIA ANTÔNIA THOMÉ';
    }
  }

  void _criarEstruturaVistoriaEntrada() {
    // Estrutura para vistoria de entrada:
    // Cabeçalho (0), Imóvel (1), Pessoas (3), Introdução (2), Observação (4), Assinaturas (9)
    setState(() {
      _ordemSecoes.clear();
      _ordemSecoes.add((instanceId: '', sectionId: 0)); // Cabeçalho
      _ordemSecoes.add((instanceId: 'i_${_instanceCounter++}', sectionId: 1)); // Imóvel
      _ordemSecoes.add((instanceId: '', sectionId: 3)); // Pessoas
      _ordemSecoes.add((instanceId: '', sectionId: 2)); // Introdução
      _ordemSecoes.add((instanceId: '', sectionId: 4)); // Observação
      _ordemSecoes.add((instanceId: 'i_${_instanceCounter++}', sectionId: 9)); // Assinaturas
      _secaoSelecionada = 0;
    });
    
    // Configurar legenda para ENTRADA (TipoLegenda.status)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _secaoLegendasKey.currentState?.setTipoLegenda(TipoLegenda.status, aplicarPadrao: true);
    });
  }

  void _criarEstruturaVistoriaSaida() {
    // Estrutura para vistoria de saída (mesma estrutura de entrada):
    // Cabeçalho (0), Imóvel (1), Pessoas (3), Introdução (2), Observação (4), Assinaturas (9)
    setState(() {
      _ordemSecoes.clear();
      _ordemSecoes.add((instanceId: '', sectionId: 0)); // Cabeçalho
      _ordemSecoes.add((instanceId: 'i_${_instanceCounter++}', sectionId: 1)); // Imóvel
      _ordemSecoes.add((instanceId: '', sectionId: 3)); // Pessoas
      _ordemSecoes.add((instanceId: '', sectionId: 2)); // Introdução
      _ordemSecoes.add((instanceId: '', sectionId: 4)); // Observação
      _ordemSecoes.add((instanceId: 'i_${_instanceCounter++}', sectionId: 9)); // Assinaturas
      _secaoSelecionada = 0;
    });
    
    // Configurar legenda para SAÍDA (TipoLegenda.inconformidade)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _secaoLegendasKey.currentState?.setTipoLegenda(TipoLegenda.inconformidade, aplicarPadrao: true);
    });
  }

  Future<void> _gerarNumeroAutomatico() async {
    final proximoNumero = await UserPreferencesService.obterProximoNumeroVistoria();
    if (mounted) {
      _numeroVistoriaController.text = proximoNumero;
    }
  }

  /// Diálogo do nome só na primeira gravação (nova vistoria sem ficheiro associado).
  bool _precisaDialogNomeAoSalvar() {
    if (widget.vistoriaArquivoPath != null && widget.vistoriaArquivoPath!.isNotEmpty) {
      return false;
    }
    if (_caminhoArquivoAtual != null && _caminhoArquivoAtual!.isNotEmpty) {
      return false;
    }
    if (kIsWeb && widget.vistoriaData != null) return false;
    if (kIsWeb && _documentoJaSalvoWeb) return false;
    return true;
  }

  Vistoria _buildVistoriaBase() {
    final legendas = _secaoLegendasKey.currentState?.getLegendas();
    if (legendas != null) _legendasCache = legendas;

    final itensObservacao = _secaoObservacoesKey.currentState?.getItensObservacao();
    if (itensObservacao != null) _itensObservacaoCache = itensObservacao;

    final imoveisNaOrdem = _ordemSecoes.where((e) => e.sectionId == 1).toList();
    final primeiroImovel = imoveisNaOrdem.isEmpty
        ? null
        : _getImovelForInstance(imoveisNaOrdem.first.instanceId);
    final protocolo = primeiroImovel?.protocolo ?? '';
    final endereco = primeiroImovel?.endereco ?? '';
    final mobiliado = primeiroImovel?.mobiliado ?? '';
    final quartos = primeiroImovel?.quartos ?? '';
    final banheiros = primeiroImovel?.banheiros ?? '';

    final tipoLegenda = _secaoLegendasKey.currentState?.getTipoLegenda();
    
    // Se nome estiver vazio, usar nome gerado automaticamente
    final nomeVistoria = _nomeVistoriaController.text.trim().isEmpty
        ? 'Vistoria ${_tipoController.text.trim().toUpperCase()} - ${_dataController.text.trim()}'
        : _nomeVistoriaController.text.trim();
    
    return Vistoria(
      nome: nomeVistoria,
      numero: _numeroVistoriaController.text.trim().isEmpty 
          ? '00001' 
          : _numeroVistoriaController.text.trim().padLeft(5, '0'),
      data: _dataController.text.trim(),
      vistoriador: _vistoriadorController.text.trim(),
      tipo: _tipoController.text.trim().toUpperCase(),
      cliente: '',
      endereco: endereco,
      protocolo: protocolo,
      // mapaLat e mapaLng não são mais usados - removido em favor de mapaBytes
      observacoes: '',
      mobiliado: mobiliado,
      quartos: quartos,
      banheiros: banheiros,
      introducao: _introducaoController.text.trim(),
      legendas: legendas ?? _legendasCache,
      tipoLegenda: tipoLegenda,
      itensObservacao: itensObservacao ?? _itensObservacaoCache,
      observacaoComplementar: _observacaoComplementarController.text.trim(),
      inconformidades: const [],
      chaves: const [],
      medidores: const [],
      ambientes: const [],
      assinaturas: const [],
      pessoas: _lerPessoas(),
    );
  }

  /// Monta a lista de conteúdo para o PDF: cada item tem sectionId e dados da instância.
  Future<List<ContentItemPdf>> _buildContentForPdf() async {
    _cachearTodasSecoes();
    final items = <ContentItemPdf>[];
    const iconSize = 24.0;
    for (final entry in _ordemSecoes) {
      if (entry.sectionId == 0) continue;
      List<DadosSubtopico>? dadosSecao;
      List<Assinatura>? assinaturas;
      ImovelData? imovelData;
      String? tituloSecaoDados;
      ModoSecaoDadosPdf? modoSecaoDados;
      Uint8List? iconBytesSecaoDados;
      String? nomeCustomizado;
      Uint8List? iconBytesCustomizado;
      
      final k = _makeKey(entry.sectionId, entry.instanceId);
      final custom = _secaoCustomConfig[k];
      if (custom != null) {
        nomeCustomizado = custom.nome;
        try {
          iconBytesCustomizado = await ScreenshotController().captureFromWidget(
            Icon(custom.icon, size: iconSize, color: AppColors.secondary),
            delay: const Duration(milliseconds: 200),
            targetSize: const Size(iconSize, iconSize),
          );
        } catch (_) {}
      }
      
      switch (entry.sectionId) {
        case 1:
          imovelData = _getImovelForInstance(entry.instanceId);
          // Se não houver ícone customizado, usar Icons.apartment como padrão
          if (iconBytesCustomizado == null) {
            try {
              iconBytesCustomizado = await ScreenshotController().captureFromWidget(
                Icon(Icons.apartment_outlined, size: iconSize, color: AppColors.secondary),
                delay: const Duration(milliseconds: 200),
                targetSize: const Size(iconSize, iconSize),
              );
            } catch (_) {}
          }
          break;
        case 2:
          // Se não houver ícone customizado, usar Icons.note como padrão
          if (iconBytesCustomizado == null) {
            try {
              iconBytesCustomizado = await ScreenshotController().captureFromWidget(
                Icon(Icons.note_outlined, size: iconSize, color: AppColors.secondary),
                delay: const Duration(milliseconds: 200),
                targetSize: const Size(iconSize, iconSize),
              );
            } catch (_) {}
          }
          break;
        case 3:
          // Se não houver ícone customizado, usar Icons.groups como padrão
          if (iconBytesCustomizado == null) {
            try {
              iconBytesCustomizado = await ScreenshotController().captureFromWidget(
                Icon(Icons.groups, size: iconSize, color:  AppColors.secondary),
                delay: const Duration(milliseconds: 200),
                targetSize: const Size(iconSize, iconSize),
              );
            } catch (_) {}
          }
          break;
        case 5:
          dadosSecao = _getDadosForInstance(entry.instanceId);
          final k = _makeKey(5, entry.instanceId);
          final cfg = _secaoDadosConfig[k];
          final t = (cfg?.titulo ?? '').trim();
          tituloSecaoDados = t.isNotEmpty ? t : null;
          modoSecaoDados = cfg?.modo ?? ModoSecaoDadosPdf.padrao;
          if (cfg != null && iconBytesCustomizado == null) {
            try {
              iconBytesSecaoDados = await ScreenshotController().captureFromWidget(
                Icon(cfg.iconData, size: iconSize, color: AppColors.secondary),
                delay: const Duration(milliseconds: 200),
                targetSize: const Size(iconSize, iconSize),
              );
            } catch (_) {}
          }
          break;
        case 9:
          // Se não houver ícone customizado, usar Icons.draw como padrão
          if (iconBytesCustomizado == null) {
            try {
              iconBytesCustomizado = await ScreenshotController().captureFromWidget(
                Icon(Icons.draw, size: iconSize, color: AppColors.secondary),
                delay: const Duration(milliseconds: 200),
                targetSize: const Size(iconSize, iconSize),
              );
            } catch (_) {}
          }
          assinaturas = _getAssinaturasForInstance(entry.instanceId);
          break;
      }
      items.add(ContentItemPdf(
        sectionId: entry.sectionId,
        dadosSecao: dadosSecao,
        assinaturas: assinaturas,
        imovelData: imovelData,
        tituloSecaoDados: tituloSecaoDados?.isNotEmpty == true ? tituloSecaoDados : null,
        modoSecaoDados: modoSecaoDados,
        iconBytesSecaoDados: iconBytesSecaoDados,
        nomeCustomizado: nomeCustomizado,
        iconBytesCustomizado: iconBytesCustomizado,
      ));
    }
    return items;
  }

  Future<void> _atualizarPreview() async {
    if (!mounted) return;
    setState(() {
      _isLoadingPreview = true;
      _previewError = null;
    });
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;
    try {
      final vistoria = _buildVistoriaBase();
      final contentOrder = await _buildContentForPdf();
      final bytes = await PdfService.gerarBytes(
        vistoria,
        includeMapa: true,
        contentOrder: contentOrder,
        imageResolver: PdfImageResolver.withDrive(appDriveService),
      );
      if (!mounted) return;
      if (kIsWeb) {
        openPdfBytesInNewTab(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('PDF aberto numa nova aba no navegador.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      }
      setState(() {
        _pdfBytes = bytes;
        _isLoadingPreview = false;
        _previewError = null;
        _previewVersion++;
      });
    } catch (e, st) {
      debugPrint('Preview PDF error: $e');
      debugPrint('$st');
      if (mounted) {
        setState(() {
          _isLoadingPreview = false;
          _previewError = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    openDrivePanelCallback = null;
    _pdfViewerController.dispose();
    _nomeVistoriaController.dispose();
    _numeroVistoriaController.dispose();
    _dataController.dispose();
    _vistoriadorController.dispose();
    _tipoController.dispose();
    _introducaoController.dispose();
    _observacaoComplementarController.dispose();
    for (final p in _pessoasFields) {
      p.dispose();
    }
    super.dispose();
  }

  void _adicionarPessoa() {
    final index = _pessoasFields.length + 1;
    final p = _PessoaControllers();
    p.nome.text = 'Nome da pessoa $index';
    p.cpfCnpj.text = index == 1 ? '000.000.000-00' : '00.000.000/0001-00';
    p.funcao.text = index == 1 ? 'LOCADOR' : 'LOCATÁRIO';
    setState(() => _pessoasFields.add(p));
  }

  void _removerPessoa(int index) {
    if (_pessoasFields.length <= 1) return;
    setState(() {
      _pessoasFields[index].dispose();
      _pessoasFields.removeAt(index);
    });
  }

  List<Pessoa> _lerPessoas() {
    return _pessoasFields
        .map((p) => Pessoa(
              nome: p.nome.text.trim(),
              cpfCnpj: p.cpfCnpj.text.trim(),
              funcao: p.funcao.text.trim(),
            ))
        .toList();
  }

  static const _itensMenu = [
    (sectionId: 0, icon: Icons.info_outline, label: 'Cabeçalho'),
    (sectionId: 1, icon: Icons.home_outlined, label: 'Imóvel'),
    (sectionId: 2, icon: Icons.note, label: 'Introdução'),
    (sectionId: 3, icon: Icons.groups, label: 'Pessoas'),
    (sectionId: 4, icon: Icons.visibility, label: 'Observação'),
    (sectionId: 5, icon: Icons.list_alt, label: 'Seção de dados'),
    (sectionId: 9, icon: Icons.draw, label: 'Assinaturas'),
  ];

  /// Configuração por instância da seção de dados (título, ícone, modo).
  final Map<String, ({String titulo, IconData iconData, ModoSecaoDadosPdf modo})> _secaoDadosConfig = {};
  
  /// Configuração customizada de nome e ícone para qualquer seção
  final Map<String, ({String nome, IconData icon})> _secaoCustomConfig = {};

  (IconData icon, String label) _getMenuItem(int sectionId) {
    for (final item in _itensMenu) {
      if (item.sectionId == sectionId) return (item.icon, item.label);
    }
    return (Icons.help_outline, 'Seção');
  }

  String _getMenuLabel(int index) {
    final entry = _ordemSecoes[index];
    final k = _makeKey(entry.sectionId, entry.instanceId);
    
    // Verificar se tem configuração customizada
    final custom = _secaoCustomConfig[k];
    if (custom != null && custom.nome.isNotEmpty) {
      return custom.nome;
    }
    
    if (entry.sectionId == 5) {
      final cfg = _secaoDadosConfig[_makeKey(5, entry.instanceId)];
      return cfg?.titulo.isNotEmpty == true ? cfg!.titulo : 'Seção de dados';
    }
    return _getMenuItem(entry.sectionId).$2;
  }

  IconData _getMenuIcon(int index) {
    final entry = _ordemSecoes[index];
    final k = _makeKey(entry.sectionId, entry.instanceId);
    
    // Verificar se tem configuração customizada
    final custom = _secaoCustomConfig[k];
    if (custom != null) {
      return custom.icon;
    }
    
    if (entry.sectionId == 5) {
      final cfg = _secaoDadosConfig[_makeKey(5, entry.instanceId)];
      return cfg?.iconData ?? Icons.list_alt;
    }
    return _getMenuItem(entry.sectionId).$1;
  }

  Future<void> _editarSecao(int index) async {
    final entry = _ordemSecoes[index];
    final k = _makeKey(entry.sectionId, entry.instanceId);
    
    // Obter valores atuais
    String nomeAtual = _getMenuLabel(index);
    IconData iconeAtual = _getMenuIcon(index);
    
    // Se for seção 5, usar configuração existente
    if (entry.sectionId == 5) {
      final cfg = _secaoDadosConfig[_makeKey(5, entry.instanceId)];
      if (cfg != null) {
        nomeAtual = cfg.titulo;
        iconeAtual = cfg.iconData;
      }
    }
    
    final nomeController = TextEditingController(text: nomeAtual);
    IconData? iconeSelecionado = iconeAtual;
    
    final resultado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.edit, color: Color(0xFF00C896), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Editar Seção',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nomeController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da seção',
                    hintText: 'Ex: Cabeçalho, Imóvel, Introdução',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 20),
                const Text(
                  'Ícone da seção',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () async {
                    final icon = await showIconPicker(
                      context,
                      configuration: SinglePickerConfiguration(
                        iconPackModes: [IconPack.material],
                        title: const Text('Escolher ícone'),
                        iconSize: 48,
                        iconColor: const Color(0xFF000080),
                        showSearchBar: true,
                        showTooltips: false,
                      ),
                    );
                    if (icon != null) {
                      setDialogState(() {
                        iconeSelecionado = icon.data;
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(iconeSelecionado, size: 32, color: const Color(0xFF000080)),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Toque para escolher outro ícone',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                        const Icon(Icons.chevron_right, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            // Botão de excluir (apenas se não for cabeçalho)
            if (entry.sectionId != 0)
              TextButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx); // Fechar diálogo de edição primeiro
                  await _removerSecao(index);
                },
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Excluir'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, {
                'nome': nomeController.text.trim(),
                'icone': iconeSelecionado,
              }),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
              ),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    if (resultado != null && resultado['nome'] != null && resultado['icone'] != null) {
      setState(() {
        final nome = resultado['nome'] as String;
        final icone = resultado['icone'] as IconData;
        
        // Se for seção 5, atualizar também a configuração de dados
        if (entry.sectionId == 5) {
          final cfg = _secaoDadosConfig[_makeKey(5, entry.instanceId)];
          if (cfg != null) {
            _secaoDadosConfig[_makeKey(5, entry.instanceId)] = (
              titulo: nome,
              iconData: icone,
              modo: cfg.modo,
            );
          } else {
            _secaoDadosConfig[_makeKey(5, entry.instanceId)] = (
              titulo: nome,
              iconData: icone,
              modo: ModoSecaoDadosPdf.padrao,
            );
          }
        } else {
          // Para outras seções, salvar na configuração customizada
          _secaoCustomConfig[k] = (nome: nome, icon: icone);
        }
      });
    }
  }

  Future<void> _abrirSeletorIcone(String k) async {
    final icon = await showIconPicker(
      context,
      configuration: SinglePickerConfiguration(
        iconPackModes: [IconPack.material],
        title: const Text('Escolher ícone'),
        iconSize: 48,
        iconColor: const Color(0xFF000080),
        showSearchBar: true,
        showTooltips: false,
      ),
    );
    if (icon != null && mounted) {
      setState(() {
        final c2 = _secaoDadosConfig[k];
        if (c2 != null) {
          _secaoDadosConfig[k] = (titulo: c2.titulo, iconData: icon.data, modo: c2.modo);
        } else {
          _secaoDadosConfig[k] = (titulo: 'Seção', iconData: icon.data, modo: ModoSecaoDadosPdf.padrao);
        }
      });
    }
  }

  void _abrirDialogAdicionarSecao() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C896).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.add_circle, color: Color(0xFF00C896), size: 28),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Adicionar Seção',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000080),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Escolha o tipo de seção que deseja adicionar à vistoria',
                style: TextStyle(color: Colors.grey, fontSize: 14),
              ),
              const SizedBox(height: 24),
              Flexible(
                child: GridView.builder(
                  shrinkWrap: true,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 2.5,
                  ),
                  itemCount: _itensMenu.length - 1, // Exclui cabeçalho
                  itemBuilder: (context, index) {
                    final item = _itensMenu[index + 1];
                    final podeRepetir = _isSecaoDuplicavel(item.sectionId);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          _cacheSecaoAtual();
                          setState(() {
                            final instanceId = podeRepetir ? 'i_${_instanceCounter++}' : '';
                            _ordemSecoes = [..._ordemSecoes, (instanceId: instanceId, sectionId: item.sectionId)];
                            _secaoSelecionada = _ordemSecoes.length - 1;
                            if (item.sectionId == 5) {
                              _secaoDadosConfig[_makeKey(5, instanceId)] = (
                                titulo: 'Seção',
                                iconData: Icons.list_alt,
                                modo: ModoSecaoDadosPdf.padrao,
                              );
                            }
                          });
                          Navigator.of(ctx).pop();
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey[300]!),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.05),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF000080).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(item.icon, color: const Color(0xFF000080), size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 14,
                                        color: Color(0xFF000080),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    if (podeRepetir)
                                      Text(
                                        'Pode repetir',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: Colors.grey[400], size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConteudoSecao(String instanceId, int sectionId) {
    switch (sectionId) {
      case 0:
        return _buildSecaoCabecalho();
      case 1:
        return _buildSecaoImovel(instanceId);
      case 2:
        return _buildSecaoIntroducao();
      case 3:
        return _buildSecaoPessoas();
      case 4:
        return _buildSecaoObservacao();
      case 5:
        return _buildSecaoDadosCustom(instanceId);
      case 9:
        return _buildSecaoAssinaturas(instanceId);
      default:
        return const SizedBox();
    }
  }

  Widget _buildSecaoCabecalho() {
    // Se o tipo já foi definido na tela welcome, não mostrar o campo tipo
    final tipoJaDefinido = widget.tipoInicial != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _nomeVistoriaController,
          decoration: const InputDecoration(
            labelText: 'Nome da Vistoria',
            hintText: 'Ex: Vistoria Apartamento 101',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.title),
            helperText: 'Nome gerado automaticamente (pode ser editado)',
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _numeroVistoriaController,
          decoration: const InputDecoration(
            labelText: 'Número da Vistoria',
            hintText: 'Ex: 00001',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.numbers),
            helperText: 'Número gerado automaticamente (pode ser editado)',
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _dataController,
          decoration: const InputDecoration(
            labelText: 'Data',
            hintText: 'Ex: 15/01/2026',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.calendar_today),
            helperText: 'Data preenchida automaticamente (pode ser editada)',
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe a data' : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _vistoriadorController,
          decoration: const InputDecoration(
            labelText: 'Vistoriador',
            hintText: 'Nome do vistoriador',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.person),
            helperText: 'Vistoriador salvo automaticamente (pode ser editado)',
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o vistoriador' : null,
          onChanged: (value) {
            // Salvar vistoriador quando o usuário digitar
            if (value.trim().isNotEmpty) {
              UserPreferencesService.salvarVistoriadorPadrao(value.trim());
            }
          },
        ),
        // Só mostrar campo tipo se não foi definido na tela welcome
        if (!tipoJaDefinido) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _tipoController,
            decoration: const InputDecoration(
              labelText: 'Tipo',
              hintText: 'Ex: ENTRADA ou SAÍDA',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.swap_horiz),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o tipo' : null,
          ),
        ],
      ],
    );
  }

  Widget _buildSecaoImovel(String instanceId) {
    final key = _obterKeySecaoImovel(instanceId);
    final k = _makeKey(1, instanceId);
    
    // Sempre fazer cache dos dados atuais antes de reconstruir (se o widget já existe)
    final dadosAtuais = key.currentState?.getDados();
    if (dadosAtuais != null) {
      _imovelCache[k] = dadosAtuais;
    }
    
    final dadosCache = _imovelCache[k];
    
    // Carregar dados do cache após o widget ser montado
    if (dadosCache != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (key.currentState != null && mounted) {
          key.currentState?.carregarDados(dadosCache);
        }
      });
    }
    
    return SecaoImovel(key: key);
  }

  Widget _buildSecaoIntroducao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _introducaoController,
          decoration: const InputDecoration(
            labelText: 'Texto de introdução',
            hintText: 'Vistoria imobiliária profissional...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.article),
            alignLabelWithHint: true,
          ),
          maxLines: 15,
          minLines: 10,
        ),
        const SizedBox(height: 20),
        SecaoLegendas(key: _secaoLegendasKey),
        const SizedBox(height: 20),
        const Text(
          'OBSERVAÇÃO COMPLEMENTAR',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Color(0xFF000080),
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _observacaoComplementarController,
          decoration: const InputDecoration(
            labelText: 'Observação complementar',
            hintText: 'Ex: Nos casos em que o imóvel ainda se encontra ocupado...',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.note),
            alignLabelWithHint: true,
          ),
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _buildSecaoPessoas() {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 420),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'NOME | CPF/CNPJ | FUNÇÃO',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),
          ...List.generate(_pessoasFields.length, (index) => _buildPessoaCard(index)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _adicionarPessoa,
          icon: const Icon(Icons.person_add),
          label: const Text('Adicionar pessoa'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF000080),
            side: const BorderSide(color: Color(0xFF00C896)),
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildSecaoObservacao() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Lista de observações com bullet. Cada item pode ter uma cor diferente.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
        const SizedBox(height: 16),
        SecaoObservacoes(key: _secaoObservacoesKey, exibirComoTopico: true),
      ],
    );
  }

  Widget _buildSecaoDadosCustom(String instanceId) {
    final k = _makeKey(5, instanceId);
    var cfg = _secaoDadosConfig[k];
    if (cfg == null) {
      cfg = (titulo: 'Seção', iconData: Icons.list_alt, modo: ModoSecaoDadosPdf.padrao);
      _secaoDadosConfig[k] = cfg;
    }
    final config = cfg;
    final iconData = config.iconData;
    final modo = config.modo == ModoSecaoDadosPdf.ambientes
        ? ModoSecaoDados.ambientes
        : config.modo == ModoSecaoDadosPdf.medidores
            ? ModoSecaoDados.medidores
            : config.modo == ModoSecaoDadosPdf.detalhado
                ? ModoSecaoDados.detalhado
                : config.modo == ModoSecaoDadosPdf.imagens
                    ? ModoSecaoDados.imagens
                    : ModoSecaoDados.padrao;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(iconData, size: 32, color: const Color(0xFF000080)),
          title: const Text('Ícone da seção'),
          subtitle: const Text('Toque para escolher outro ícone'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _abrirSeletorIcone(k),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Colors.grey),
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ModoSecaoDadosPdf>(
          value: config.modo,
          decoration: const InputDecoration(
            labelText: 'Modo',
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: ModoSecaoDadosPdf.padrao, child: Text('Padrão (subtópicos com itens)')),
            DropdownMenuItem(value: ModoSecaoDadosPdf.medidores, child: Text('Medidores (leitura e data)')),
            DropdownMenuItem(value: ModoSecaoDadosPdf.ambientes, child: Text('Ambientes (status e observação)')),
            DropdownMenuItem(value: ModoSecaoDadosPdf.detalhado, child: Text('Detalhado (tópicos numerados com dados e informações)')),
            DropdownMenuItem(value: ModoSecaoDadosPdf.imagens, child: Text('Imagens (apenas imagens com título e link)')),
          ],
          onChanged: (v) {
            if (v != null) setState(() {
              _secaoDadosConfig[k] = (titulo: config.titulo, iconData: config.iconData, modo: v);
            });
          },
        ),
        const SizedBox(height: 20),
        SecaoDados(
          key: _obterKeySecaoDados(5, instanceId),
          titulo: () {
            final t = config.titulo.trim();
            return t.isNotEmpty ? t.toUpperCase() : 'SEÇÃO';
          }(),
          icone: iconData,
          legendaPadrao: () {
            final t = config.titulo.trim();
            return t.isNotEmpty ? t : 'Item';
          }(),
          modo: modo,
          showCamposLeituraData: config.modo == ModoSecaoDadosPdf.medidores,
          legendas: modo == ModoSecaoDados.detalhado ? (_secaoLegendasKey.currentState?.getLegendas() ?? []) : null,
        ),
      ],
    );
  }

  Widget _buildSecaoAssinaturas(String instanceId) {
    return SecaoAssinaturas(key: _obterKeySecaoAssinaturas(instanceId));
  }

  Widget _buildPessoaCard(int index) {
    final p = _pessoasFields[index];
    final podeRemover = _pessoasFields.length > 1;
    return Card(
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
                  'Pessoa ${index + 1}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000080),
                  ),
                ),
                if (podeRemover)
                  IconButton(
                    onPressed: () => _removerPessoa(index),
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Colors.red,
                    tooltip: 'Remover pessoa',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: p.nome,
              decoration: const InputDecoration(
                labelText: 'Nome',
                hintText: 'Ex: GM7 ASSESSORIA IMOBILIÁRIA LTDA',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.badge),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: p.cpfCnpj,
              decoration: const InputDecoration(
                labelText: 'CPF/CNPJ',
                hintText: 'Ex: 31.981.504/0001-63 ou 943.380.009-53',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: p.funcao,
              decoration: const InputDecoration(
                labelText: 'Função',
                hintText: 'Ex: ADMINISTRADOR, LOCADOR, LOCATÁRIO, VISTORIADOR',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.work),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _gerarPdf() async {
    if (!_formKey.currentState!.validate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (!mounted) return;

    final vistoria = _buildVistoriaBase();
    final contentOrder = await _buildContentForPdf();
    await PdfService.gerarDownload(
      vistoria,
      contentOrder: contentOrder,
      imageResolver: PdfImageResolver.withDrive(appDriveService),
    );
  }

  Future<void> _salvarVistoria() async {
    // Validar campos obrigatórios e coletar lista de erros
    final camposFaltando = <String>[];
    
    if (_dataController.text.trim().isEmpty) {
      camposFaltando.add('Data');
    }
    if (_vistoriadorController.text.trim().isEmpty) {
      camposFaltando.add('Vistoriador');
    }
    if (widget.tipoInicial == null && _tipoController.text.trim().isEmpty) {
      camposFaltando.add('Tipo');
    }
    
    if (camposFaltando.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Preencha os campos obrigatórios: ${camposFaltando.join(', ')}'),
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }
    
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final pedirNome = _precisaDialogNomeAoSalvar();
    String nomeParaFicheiro;

    if (pedirNome) {
      final nomeController = TextEditingController();
      if (_nomeVistoriaController.text.trim().isNotEmpty) {
        nomeController.text = _nomeVistoriaController.text.trim();
      } else {
        nomeController.text = 'Vistoria #${_numeroVistoriaController.text.trim()}';
      }

      final resultado = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C896).withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.save, color: Color(0xFF00C896), size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Guardar documento',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: TextField(
            controller: nomeController,
            decoration: const InputDecoration(
              labelText: 'Nome do ficheiro / vistoria',
              hintText: 'Ex: Vistoria Apartamento 101',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.title),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {'nome': nomeController.text.trim()}),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00C896),
              ),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );

      if (resultado == null || resultado['nome'] == null || (resultado['nome'] as String).isEmpty) {
        return;
      }
      nomeParaFicheiro = resultado['nome'] as String;
    } else {
      nomeParaFicheiro = _nomeVistoriaController.text.trim().isEmpty
          ? 'vistoria'
          : _nomeVistoriaController.text.trim();
    }

    try {
      _cachearTodasSecoes();
      
      final legendas = _secaoLegendasKey.currentState?.getLegendas();
      if (legendas != null) _legendasCache = legendas;
      
      final itensObservacao = _secaoObservacoesKey.currentState?.getItensObservacao();
      if (itensObservacao != null) _itensObservacaoCache = itensObservacao;
      
      final vistoria = _buildVistoriaBase();
      final contentOrder = await _buildContentForPdf();
      
      final secoesSemCabecalho = _ordemSecoes.where((e) => e.sectionId != 0).toList();
      final contentOrderData = contentOrder.asMap().entries.map((entry) {
        final index = entry.key;
        final item = entry.value;
        String? iconBase64;
        if (item.iconBytesSecaoDados != null) {
          iconBase64 = base64Encode(item.iconBytesSecaoDados!);
        }
        
        String? nomeCustomizado;
        String? iconeCustomizado;
        if (index < secoesSemCabecalho.length) {
          final secaoEntry = secoesSemCabecalho[index];
          final k = _makeKey(secaoEntry.sectionId, secaoEntry.instanceId);
          final custom = _secaoCustomConfig[k];
          if (custom != null) {
            nomeCustomizado = custom.nome;
            iconeCustomizado = custom.icon.codePoint.toString();
          }
        }
        
        String? iconeSecaoDadosCodePoint;
        if (item.sectionId == 5 && index < secoesSemCabecalho.length) {
          final secaoEntry = secoesSemCabecalho[index];
          final kSecao = _makeKey(5, secaoEntry.instanceId);
          final cfgSecao = _secaoDadosConfig[kSecao];
          if (cfgSecao != null) {
            iconeSecaoDadosCodePoint = cfgSecao.iconData.codePoint.toString();
          }
        }
        
        return ContentItemPdfData(
          sectionId: item.sectionId,
          dadosSecao: item.dadosSecao,
          assinaturas: item.assinaturas,
          imovelData: item.imovelData,
          tituloSecaoDados: item.tituloSecaoDados,
          modoSecaoDados: item.modoSecaoDados?.toString().split('.').last,
          iconBytesSecaoDados: iconBase64,
          iconeSecaoDados: iconeSecaoDadosCodePoint,
          nomeCustomizado: nomeCustomizado,
          iconeCustomizado: iconeCustomizado,
        );
      }).toList();

      final vistoriaData = VistoriaData(
        vistoria: vistoria,
        contentOrder: contentOrderData,
      );

      final json = jsonEncode(vistoriaData.toJson());
      final nomeFicheiro = VistoriaDocumentFileService.nomeFicheiroSeguro(nomeParaFicheiro);
      final caminhoExistente = _caminhoArquivoAtual ?? widget.vistoriaArquivoPath;

      final path = await VistoriaDocumentFileService.salvarVistoriaJson(
        json: json,
        nomeFicheiroSugerido: nomeFicheiro,
        caminhoExistente: caminhoExistente,
      );

      if (!kIsWeb && path != null && path.isNotEmpty) {
        setState(() => _caminhoArquivoAtual = path);
      }
      if (kIsWeb) {
        setState(() => _documentoJaSalvoWeb = true);
      }

      if (!mounted) return;

      final okDesktop = path != null && path.isNotEmpty;
      if (kIsWeb || okDesktop) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              kIsWeb ? 'Documento descarregado (JSON).' : 'Documento guardado no ficheiro.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guardar cancelado.')),
        );
        return;
      }

      if (pedirNome && (kIsWeb || okDesktop)) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao guardar: $e')),
        );
      }
    }
  }

  void _carregarVistoriaData(VistoriaData data) {
    // Limpar todas as GlobalKeys antigas para evitar conflitos
    _secaoImovelKeys.clear();
    _secaoDadosKeys.clear();
    _secaoAssinaturasKeys.clear();
    _imovelCache.clear();
    _dadosCache.clear();
    _assinaturasCache.clear();
    _instanceCounter = 0;
    
    // Carregar dados básicos
    _nomeVistoriaController.text = data.vistoria.nome;
    _numeroVistoriaController.text = data.vistoria.numero;
    _dataController.text = data.vistoria.data;
    _vistoriadorController.text = data.vistoria.vistoriador;
    _tipoController.text = data.vistoria.tipo;
    _introducaoController.text = data.vistoria.introducao;
    _observacaoComplementarController.text = data.vistoria.observacaoComplementar;

    // Carregar pessoas
    _pessoasFields.clear();
    for (final pessoa in data.vistoria.pessoas) {
      final p = _PessoaControllers();
      p.nome.text = pessoa.nome;
      p.cpfCnpj.text = pessoa.cpfCnpj;
      p.funcao.text = pessoa.funcao;
      _pessoasFields.add(p);
    }
    if (_pessoasFields.isEmpty) _adicionarPessoa();

    // Carregar legendas e observações
    _legendasCache = data.vistoria.legendas;
    _itensObservacaoCache = data.vistoria.itensObservacao;
    
    // Carregar tipo de legenda e legendas (sempre carregar para limpar templates iniciais)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (data.vistoria.tipoLegenda != null) {
        _secaoLegendasKey.currentState?.setTipoLegenda(data.vistoria.tipoLegenda!, aplicarPadrao: false);
      }
      // Sempre carregar legendas (mesmo que vazias, para limpar templates iniciais)
      _secaoLegendasKey.currentState?.carregarLegendas(data.vistoria.legendas);
      
      // Sempre carregar observações (mesmo que vazias, para limpar templates iniciais)
      _secaoObservacoesKey.currentState?.carregarItensObservacao(data.vistoria.itensObservacao);
    });

    // Reconstruir ordem de seções e carregar dados
    _ordemSecoes.clear();
    _ordemSecoes.add((instanceId: '', sectionId: 0));

    for (var i = 0; i < data.contentOrder.length; i++) {
      final item = data.contentOrder[i];
      final instanceId = _isSecaoDuplicavel(item.sectionId)
          ? 'i_${_instanceCounter++}'
          : '';
      
      _ordemSecoes.add((instanceId: instanceId, sectionId: item.sectionId));
      
      final k = _makeKey(item.sectionId, instanceId);
      
      // Carregar configuração customizada de nome e ícone
      if (item.nomeCustomizado != null && item.iconeCustomizado != null) {
        try {
          final iconCodePoint = int.parse(item.iconeCustomizado!);
          final iconData = IconData(iconCodePoint, fontFamily: 'MaterialIcons');
          _secaoCustomConfig[k] = (nome: item.nomeCustomizado!, icon: iconData);
        } catch (e) {
          debugPrint('Erro ao carregar ícone customizado: $e');
        }
      }

      if (item.sectionId == 1 && item.imovelData != null) {
        _imovelCache[k] = item.imovelData!;
      } else if (item.sectionId == 5) {
        // Carregar dados da seção
        if (item.dadosSecao != null) {
          _dadosCache[k] = item.dadosSecao!;
        }
        
        // Carregar título
        final titulo = item.tituloSecaoDados ?? 'Seção';
        final tituloKey = _makeKey(5, instanceId);
        
        // Carregar modo
        final modo = item.modoSecaoDados != null
            ? ModoSecaoDadosPdf.values.firstWhere(
                (m) => m.toString().split('.').last == item.modoSecaoDados,
                orElse: () => ModoSecaoDadosPdf.padrao,
              )
            : ModoSecaoDadosPdf.padrao;
        
        // Atualizar ou criar configuração
        final cfgAtual = _secaoDadosConfig[tituloKey];
        // Carregar ícone salvo se existir
        IconData iconDataCarregado = cfgAtual?.iconData ?? Icons.list_alt;
        if (item.iconeSecaoDados != null) {
          try {
            final iconCodePoint = int.parse(item.iconeSecaoDados!);
            iconDataCarregado = IconData(iconCodePoint, fontFamily: 'MaterialIcons');
          } catch (e) {
            debugPrint('Erro ao carregar ícone da seção de dados: $e');
          }
        }
        _secaoDadosConfig[tituloKey] = (
          titulo: titulo,
          iconData: iconDataCarregado,
          modo: modo,
        );
        
        // Carregar dados no widget
        if (item.dadosSecao != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final key = _secaoDadosKeys[tituloKey];
            if (key?.currentState != null && mounted) {
              key!.currentState!.carregarDados(item.dadosSecao!);
            }
          });
        }
      } else if (item.sectionId == 9 && item.assinaturas != null) {
        _assinaturasCache[k] = item.assinaturas!;
        // Carregar assinaturas no widget
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final key = _secaoAssinaturasKeys[k];
          if (key?.currentState != null && mounted) {
            key!.currentState!.carregarAssinaturas(item.assinaturas!);
          }
        });
      }
    }

    setState(() {
      _secaoSelecionada = 0;
    });
  }

  Future<void> _removerSecao(int index) async {
    if (index < 0 || index >= _ordemSecoes.length) return;
    
    final entry = _ordemSecoes[index];
    
    // Não permitir remover o cabeçalho
    if (entry.sectionId == 0) return;
    
    final nomeSecao = _getMenuLabel(index);
    
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar remoção'),
        content: Text(
          'Tem certeza que deseja remover a seção "$nomeSecao"? Todos os dados desta seção serão perdidos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    
    if (confirmar != true || !mounted) return;
    
    // Limpar dados relacionados à seção
    final k = _makeKey(entry.sectionId, entry.instanceId);
    
    if (entry.sectionId == 1) {
      // Remover dados do imóvel
      _secaoImovelKeys.remove(k);
      _imovelCache.remove(k);
    } else if (entry.sectionId == 5) {
      // Remover dados da seção de dados
      _secaoDadosKeys.remove(k);
      _dadosCache.remove(k);
      _secaoDadosConfig.remove(k);
    } else if (entry.sectionId == 9) {
      // Remover dados de assinaturas
      _secaoAssinaturasKeys.remove(k);
      _assinaturasCache.remove(k);
    }
    
    // Remover configuração customizada se existir
    _secaoCustomConfig.remove(k);
    
    setState(() {
      _ordemSecoes.removeAt(index);
      
      // Ajustar índice selecionado
      if (_secaoSelecionada == index) {
        // Se a seção removida era a selecionada, selecionar a anterior ou a primeira
        _secaoSelecionada = index > 0 ? index - 1 : 0;
      } else if (_secaoSelecionada > index) {
        // Se a seção removida estava antes da selecionada, ajustar o índice
        _secaoSelecionada--;
      }
      
      // Garantir que o índice não seja maior que o tamanho da lista
      if (_secaoSelecionada >= _ordemSecoes.length) {
        _secaoSelecionada = _ordemSecoes.length - 1;
      }
    });
  }

  Future<bool> _confirmarVoltar() async {
    final resultado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar saída'),
        content: const Text(
          'Tem certeza que deseja voltar? Todas as alterações não salvas serão perdidas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    return resultado ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        // Cmd+S no macOS para atualizar preview
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): _AtualizarPreviewIntent(),
      },
      child: Actions(
        actions: {
          _AtualizarPreviewIntent: CallbackAction<_AtualizarPreviewIntent>(
            onInvoke: (_) {
              if (!_isLoadingPreview) {
                _atualizarPreview();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: PopScope(
            canPop: false,
            onPopInvoked: (didPop) async {
              if (!didPop) {
                final confirmar = await _confirmarVoltar();
                if (confirmar && context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            },
            child: Scaffold(
        appBar: AppBar(
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child:  Container(
                padding:  EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Image.asset(
                  'assets/logo.jpg',
                  width: 40,
            ),)),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Gerador de Vistoria',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Crie e gerencie suas vistorias',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.normal,
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF000080), Color(0xFF00C896)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        actions: [
          Tooltip(
            message: 'Salvar vistoria',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _salvarVistoria,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  child: const Icon(Icons.save, size: 24),
                ),
              ),
            ),
          ),
          Tooltip(
            message: kIsWeb ? 'Gerar PDF e abrir numa nova aba' : 'Atualizar preview do PDF',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isLoadingPreview
                    ? null
                    : () async {
                        await _atualizarPreview();
                      },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  child: _isLoadingPreview
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.play_arrow, size: 24),
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Baixar PDF',
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _gerarPdf,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(right: 8),
                  child: const Icon(Icons.download, size: 24),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            // Menu lateral: Simples - apenas ícone e nome
            Container(
              width: 200,
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(right: BorderSide(color: Colors.grey[200]!)),
              ),
              child: Column(
                children: [
                  // Cabeçalho simples
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.menu,
                          color: Color(0xFF000080),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Seções',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF000080),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Lista de seções
                  Expanded(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      proxyDecorator: (child, _, animation) => Material(
                        elevation: 4,
                        color: Colors.transparent,
                        child: child,
                      ),
                      onReorder: (oldIndex, newIndex) {
                        _cacheSecaoAtual();
                        setState(() {
                          final item = _ordemSecoes.removeAt(oldIndex);
                          final insertIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
                          _ordemSecoes.insert(insertIndex, item);
                          if (_secaoSelecionada == oldIndex) {
                            _secaoSelecionada = insertIndex;
                          } else if (_secaoSelecionada > oldIndex && _secaoSelecionada <= newIndex) {
                            _secaoSelecionada--;
                          } else if (_secaoSelecionada >= newIndex && _secaoSelecionada < oldIndex) {
                            _secaoSelecionada++;
                          }
                        });
                      },
                      itemCount: _ordemSecoes.length,
                      itemBuilder: (context, index) {
                        final entry = _ordemSecoes[index];
                        final icon = _getMenuIcon(index);
                        final label = _getMenuLabel(index);
                        final isSelected = _secaoSelecionada == index;
                        final temConteudo = _verificarSeTemConteudo(entry);
                        final isLast = index == _ordemSecoes.length - 1;
                        
                        return ReorderableDragStartListener(
                          key: ValueKey('${entry.instanceId}-${entry.sectionId}-$index'),
                          index: index,
                          child: _TimelineItem(
                            icon: icon,
                            label: label,
                            isSelected: isSelected,
                            temConteudo: temConteudo,
                            isLast: isLast,
                            onTap: () {
                              _cacheSecaoAtual();
                              setState(() {
                                _secaoSelecionada = index;
                              });
                            },
                          ),
                        );
                      },
                    ),
                  ),
                  // Botão adicionar
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border(
                        top: BorderSide(color: Colors.grey[200]!),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _abrirDialogAdicionarSecao,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Adicionar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF00C896),
                          side: const BorderSide(color: Color(0xFF00C896)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  // Google Drive: imagens (painel lateral)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Tooltip(
                      message: _drivePanelOpen
                          ? 'Fechar painel do Google Drive'
                          : 'Abrir imagens do Google Drive',
                      child: Material(
                        color: _drivePanelOpen
                            ? const Color(0xFF00C896).withValues(alpha: 0.15)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          onTap: () {
                            if (_drivePanelOpen) {
                              _closeDrivePanel();
                            } else {
                              unawaited(_openDrivePanel());
                            }
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_to_drive,
                                  color: _drivePanelOpen
                                      ? const Color(0xFF00C896)
                                      : const Color(0xFF000080),
                                  size: 28,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: _drivePanelOpen ? 340 : 0,
              child: Offstage(
                offstage: !_drivePanelOpen,
                child: SizedBox(
                  width: 340,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey[300]!),
                      ),
                    ),
                    child: DriveImagePanel(
                      onClose: _closeDrivePanel,
                    ),
                  ),
                ),
              ),
            ),
            // Painel de personalização da seção selecionada (no web ocupa todo o espaço à direita do Drive)
            Expanded(
              flex: 1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (kIsWeb && _previewError != null)
                    Material(
                      color: Colors.red.shade50,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: Colors.red[800], size: 22),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _previewError!,
                                style: TextStyle(fontSize: 13, color: Colors.red[900]),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 20),
                              onPressed: () => setState(() => _previewError = null),
                              tooltip: 'Fechar',
                            ),
                          ],
                        ),
                      ),
                    ),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          right: BorderSide(
                            color: kIsWeb ? Colors.grey[200]! : Colors.grey[300]!,
                          ),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(32),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                        // Cabeçalho da seção
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                const Color(0xFF000080).withOpacity(0.1),
                                const Color(0xFF00C896).withOpacity(0.1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFF00C896).withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF000080),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _getMenuIcon(_secaoSelecionada),
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _getMenuLabel(_secaoSelecionada),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF000080),
                                      ),
                                    ),
                                    if (_ordemSecoes[_secaoSelecionada].sectionId != 0)
                                      Text(
                                        'Seção ${_secaoSelecionada} de ${_ordemSecoes.length - 1}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              // Botão editar
                              IconButton(
                                icon: const Icon(Icons.edit, size: 20),
                                color: const Color(0xFF00C896),
                                onPressed: () => _editarSecao(_secaoSelecionada),
                                tooltip: 'Editar nome e ícone da seção',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 32),
                        // Conteúdo da seção
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.grey[50],
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.grey[200]!),
                          ),
                          child: IndexedStack(
                            index: _secaoSelecionada,
                            sizing: StackFit.loose,
                            children: [
                              for (var i = 0; i < _ordemSecoes.length; i++)
                                _buildConteudoSecao(
                                  _ordemSecoes[i].instanceId,
                                  _ordemSecoes[i].sectionId,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
            // Desktop: coluna de preview embutida (no web o PDF abre noutra aba — sem coluna extra)
            if (!kIsWeb)
              Expanded(
                flex: 1,
                child: Container(
                  color: Colors.grey[200],
                  child: _isLoadingPreview
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(color: Color(0xFF000080)),
                              SizedBox(height: 16),
                              Text('Gerando preview...'),
                            ],
                          ),
                        )
                      : _previewError != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 48, color: Colors.red[700]),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Erro ao gerar preview',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _previewError!,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                                      maxLines: 5,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _pdfBytes == null || _pdfBytes!.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.picture_as_pdf, size: 64, color: Colors.grey[400]),
                                      const SizedBox(height: 16),
                                      Text(
                                        'Preencha os dados ao lado e clique no\nbotão Play na barra superior para ver o PDF',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : Container(
                                  color: const Color(0xFF2D2D2D),
                                  child: SizedBox.expand(
                                    child: SfPdfViewer.memory(
                                      _pdfBytes!,
                                      key: ValueKey<int>(_previewVersion),
                                      controller: _pdfViewerController,
                                      pageSpacing: 12,
                                      canShowScrollHead: true,
                                      canShowScrollStatus: true,
                                      onDocumentLoaded: (PdfDocumentLoadedDetails details) {
                                        if (mounted) {
                                          setState(() => _previewError = null);
                                        }
                                      },
                                      onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
                                        if (mounted) {
                                          setState(() {
                                            _previewError = details.description;
                                            _pdfBytes = null;
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                ),
              ),
          ],
            ),
            if (kIsWeb && _isLoadingPreview)
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.06),
                  child: const Center(
                    child: Card(
                      elevation: 8,
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Color(0xFF000080)),
                            SizedBox(height: 16),
                            Text(
                              'A gerar PDF…',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF000080),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ), // Scaffold
            ), // PopScope
          ), // Focus
        ), // Actions
      ), // Shortcuts
    );
  }
}