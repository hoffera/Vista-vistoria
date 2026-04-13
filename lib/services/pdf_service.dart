import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

// Imports condicionais para download multiplataforma (io = VM/desktop/mobile; js_interop = web JS/Wasm)
import 'pdf_download_stub.dart'
    if (dart.library.io) 'pdf_download_io.dart'
    if (dart.library.js_interop) 'pdf_download_web.dart';

import '../models/assinatura.dart';
import '../models/dados.dart';
import '../models/imovel_data.dart';
import '../models/legenda.dart';
import '../models/observacao_item.dart';
import '../models/pessoa.dart';
import '../models/vistoria.dart';
import '../utils/colors.dart';
import '../utils/pdf_image_embed.dart';
import 'pdf_image_resolver.dart';

enum _ModoSecaoPdf { padrao, ambientes, medidores, detalhado, imagens }

/// Modo da seção de dados no PDF (equivalente a ModoSecaoDados).
enum ModoSecaoDadosPdf { padrao, ambientes, medidores, detalhado, imagens }


/// Item de conteúdo para o PDF: sectionId + dados da instância.
class ContentItemPdf {
  final int sectionId;
  final List<DadosSubtopico>? dadosSecao;
  final List<Assinatura>? assinaturas;
  final ImovelData? imovelData;
  /// Título customizado para seção de dados (sectionId 5).
  final String? tituloSecaoDados;
  /// Modo da seção de dados (padrao, ambientes, medidores).
  final ModoSecaoDadosPdf? modoSecaoDados;
  /// Ícone renderizado como PNG (para seção de dados).
  final Uint8List? iconBytesSecaoDados;
  /// Nome customizado da seção (para qualquer seção).
  final String? nomeCustomizado;
  /// Ícone customizado renderizado como PNG (para qualquer seção).
  final Uint8List? iconBytesCustomizado;

  const ContentItemPdf({
    required this.sectionId,
    this.dadosSecao,
    this.assinaturas,
    this.imovelData,
    this.tituloSecaoDados,
    this.modoSecaoDados,
    this.iconBytesSecaoDados,
    this.nomeCustomizado,
    this.iconBytesCustomizado,
  });
}

class PdfService {
  /// Margem esquerda do conteúdo (header + dados)
  static const double _marginLeft = 0.0;
  /// Padding horizontal para texto corrido (evita corte nas bordas) – aplicado nos dois lados
  static const double _paddingTextoHorizontal = 12.0;
  /// Altura do footer (template) - não desenhar conteúdo abaixo disso
  static const double _footerHeight = 50.0;
  
  /// Converte uma cor Flutter para PdfColor
  static PdfColor _colorToPdfColor(Color color) {
    return PdfColor(
      (color.r * 255.0).round().clamp(0, 255),
      (color.g * 255.0).round().clamp(0, 255),
      (color.b * 255.0).round().clamp(0, 255),
    );
  }
  /// Margem de segurança acima do footer (evita conteúdo após o rodapé)
  static const double _marginBottom = 10.0;
  /// Altura A4 em pontos
  static const double _pageHeightA4 = 841.89;
  /// Altura máxima Y para conteúdo (evita sobrepor o footer)
  static const double _maxContentY = _pageHeightA4 - _footerHeight - _marginBottom;

  /// Downloads em paralelo (Drive/HTTP) e redução de resolução antes do [PdfBitmap].
  static const int _preloadConcurrency = 8;

  static Future<Map<String, Uint8List?>> _preloadResolvedImages(
    List<ContentItemPdf> ordem,
    PdfImageResolver resolver,
    bool includeMapa,
  ) async {
    final map = <String, Uint8List?>{};

    final mapaPorChave = <String, ImovelData>{};
    final dadosPorChave = <String, DadosImagem>{};

    for (final item in ordem) {
      if (item.sectionId == 1 && includeMapa && item.imovelData != null) {
        final im = item.imovelData!;
        mapaPorChave.putIfAbsent(pdfImageKeyMapa(im), () => im);
      }
      if (item.sectionId == 5 && item.dadosSecao != null) {
        for (final sub in item.dadosSecao!) {
          for (final it in sub.itens) {
            for (final img in it.imagens) {
              dadosPorChave.putIfAbsent(pdfImageKeyDados(img), () => img);
            }
          }
          for (final img in sub.imagens) {
            dadosPorChave.putIfAbsent(pdfImageKeyDados(img), () => img);
          }
        }
      }
    }

    Future<void> carregarLote<T>(
      List<MapEntry<String, T>> entradas,
      Future<Uint8List?> Function(T ref) baixar,
      Future<Uint8List?> Function(Uint8List? raw) otimizar,
    ) async {
      for (var i = 0; i < entradas.length; i += _preloadConcurrency) {
        final lote = entradas.skip(i).take(_preloadConcurrency).toList();
        await Future.wait(
          lote.map((e) async {
            final raw = await baixar(e.value);
            map[e.key] = await otimizar(raw);
          }),
        );
      }
    }

    await carregarLote(
      mapaPorChave.entries.toList(),
      (im) => resolver.resolveMapa(im),
      PdfImageEmbed.encodeForMapa,
    );

    await carregarLote(
      dadosPorChave.entries.toList(),
      (img) => resolver.resolveDadosImagem(img),
      PdfImageEmbed.encodeForDadosFoto,
    );

    return map;
  }

  static Uint8List? _bytesForDadosImagem(DadosImagem img, Map<String, Uint8List?> m) =>
      m[pdfImageKeyDados(img)];

  /// Gera o PDF e retorna os bytes (para preview ou download).
  /// [includeMapa] = false para preview rápido (pula resolução do mapa).
  /// [contentOrder] = lista com dados por instância para seções duplicáveis.
  /// [imageResolver] resolve URLs públicas e arquivos do Google Drive para bytes.
  static Future<Uint8List> gerarBytes(
    Vistoria vistoria, {
    bool includeMapa = true,
    List<ContentItemPdf>? contentOrder,
    PdfImageResolver? imageResolver,
  }) async {
    final resolver = imageResolver ?? PdfImageResolver.withDrive(null);
    final defaultOrder = [
      const ContentItemPdf(sectionId: 1),
      const ContentItemPdf(sectionId: 3),
      const ContentItemPdf(sectionId: 2),
      const ContentItemPdf(sectionId: 5, tituloSecaoDados: 'INCONFORMIDADES'),
      const ContentItemPdf(sectionId: 9),
    ];
    final ordem = contentOrder ?? defaultOrder;

    final resolvedImages = await _preloadResolvedImages(ordem, resolver, includeMapa);

    final document = PdfDocument();
    document.pageSettings.margins
      ..left = 40
      ..right = 40
      ..top = 20
      ..bottom = 0;

    await _configurarFooterTemplate(document, vistoria);

    PdfPage page = document.pages.add();
    double currentY = 200;

    await desenharCabecalho(
      page,
      vistoria.data,
      vistoria.vistoriador,
      vistoria.tipo,
    );

    for (final item in ordem) {
      final id = item.sectionId;
      switch (id) {
        case 1:
          final imovel = item.imovelData;
          final identificacao = imovel?.protocolo ?? vistoria.protocolo;
          final endereco = imovel?.endereco ?? vistoria.endereco;
          final mobiliado = imovel?.mobiliado ?? vistoria.mobiliado;
          final quartos = imovel?.quartos ?? vistoria.quartos;
          final banheiros = imovel?.banheiros ?? vistoria.banheiros;
          Uint8List? mapaBytes;
          if (includeMapa && imovel != null) {
            mapaBytes = resolvedImages[pdfImageKeyMapa(imovel)];
          }
          (page, currentY) = _desenharImovelComPagina(
            document,
            page,
            startY: currentY,
            identificacao: identificacao,
            endereco: endereco,
            mobiliado: mobiliado,
            quartos: quartos,
            banheiros: banheiros,
            mapaBytes: mapaBytes,
            nomeCustomizado: item.nomeCustomizado,
            iconBytesCustomizado: item.iconBytesCustomizado,
          );
          break;
        case 2:
          (page, currentY) = _desenharIntroducaoComPagina(
            document,
            page,
            startY: currentY,
            introducao: vistoria.introducao,
            legendas: vistoria.legendas,
            itensObservacao: vistoria.itensObservacao,
            observacaoComplementar: vistoria.observacaoComplementar,
            tipoVistoria: vistoria.tipo,
            tipoLegenda: vistoria.tipoLegenda,
            nomeCustomizado: item.nomeCustomizado,
            iconBytesCustomizado: item.iconBytesCustomizado,
          );
          break;
        case 3:
          (page, currentY) = _desenharPessoasComPagina(
            document,
            page,
            startY: currentY,
            pessoas: vistoria.pessoas,
            nomeCustomizado: item.nomeCustomizado,
            iconBytesCustomizado: item.iconBytesCustomizado,
          );
          break;
        case 4:
          (page, currentY) = desenharIntroducao(
            document,
            page,
            startY: currentY,
            introducao: '',
            legendas: [],
            itensObservacao: vistoria.itensObservacao,
            observacaoComplementar: '',
            apenasObservacao: true,
            tipoVistoria: vistoria.tipo,
            tipoLegenda: vistoria.tipoLegenda,
            nomeCustomizado: item.nomeCustomizado,
            iconBytesCustomizado: item.iconBytesCustomizado,
          );
          break;
        case 5:
          final titulo = item.nomeCustomizado ?? item.tituloSecaoDados ?? 'SEÇÃO';
          final modo = item.modoSecaoDados == ModoSecaoDadosPdf.ambientes
              ? _ModoSecaoPdf.ambientes
              : item.modoSecaoDados == ModoSecaoDadosPdf.medidores
                  ? _ModoSecaoPdf.medidores
                  : item.modoSecaoDados == ModoSecaoDadosPdf.detalhado
                      ? _ModoSecaoPdf.detalhado
                      : item.modoSecaoDados == ModoSecaoDadosPdf.imagens
                          ? _ModoSecaoPdf.imagens
                          : _ModoSecaoPdf.padrao;
          (page, currentY) = _desenharSecaoDados(
            document,
            page,
            startY: currentY,
            titulo: titulo.toUpperCase(),
            dados: item.dadosSecao ?? [],
            modo: modo,
            iconBytes: item.iconBytesCustomizado ?? item.iconBytesSecaoDados,
            legendas: vistoria.legendas,
            resolvedImageBytes: resolvedImages,
          );
          break;
        case 9:
          (page, currentY) = await _desenharAssinaturas(
            document,
            page,
            startY: currentY,
            assinaturas: item.assinaturas ?? vistoria.assinaturas,
            nomeCustomizado: item.nomeCustomizado,
            iconBytesCustomizado: item.iconBytesCustomizado,
          );
          break;
      }
    }

    final bytes = await document.save();
    document.dispose();
    return Uint8List.fromList(bytes);
  }

  /// Configura o footer via document.template.bottom (conforme doc Syncfusion).
  static Future<void> _configurarFooterTemplate(
    PdfDocument document,
    Vistoria vistoria,
  ) async {
    const footerWidth = 595.0;
    const footerHeight = 50.0;
    const footerLogoSize = 28.0;
    final footerElement = PdfPageTemplateElement(
      Rect.fromLTWH(0, 0, footerWidth, footerHeight),
    );

    final g = footerElement.graphics;
    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final fontPequena = PdfStandardFont(PdfFontFamily.helvetica, 8);
    final fontNormal = PdfStandardFont(PdfFontFamily.helvetica, 9);

    // Esquerda: logo + texto gerado colado (posicionados na base do footer)
    const paddingBottom = 10.0;
    final logoY = footerHeight - footerLogoSize - paddingBottom;
    final ByteData dataLogo = await rootBundle.load('assets/logo.jpg');
    final logo = PdfBitmap(dataLogo.buffer.asUint8List());
    g.drawImage(logo, Rect.fromLTWH(0, logoY, footerLogoSize, footerLogoSize));

    final now = DateTime.now();
    final textoGerado =
        'Gerado no dia ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} às '
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    g.drawString(
      textoGerado,
      fontNormal,
      brush: brushPreto,
      bounds: Rect.fromLTWH(footerLogoSize + 8, logoY + 4, footerWidth - footerLogoSize - 180, 16),
    );

    // Direita: Página X de Y (campos dinâmicos Syncfusion)
    final pageNum = PdfPageNumberField(font: fontNormal, brush: brushAzul);
    final pageCount = PdfPageCountField(font: fontNormal, brush: brushAzul);
    final compositePage = PdfCompositeField(
      font: fontNormal,
      brush: brushAzul,
      text: 'Página {0} de {1}',
      fields: [pageNum, pageCount],
    );
    compositePage.draw(g, Offset(footerWidth - 140, logoY));

    final numeroVistoria = vistoria.numero.isNotEmpty ? vistoria.numero : '00001';
    g.drawString(
      'VISTORIA: #$numeroVistoria',
      fontPequena,
      brush: brushPreto,
      bounds: Rect.fromLTWH(footerWidth - 140, logoY + 16, 130, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );

    footerElement.dock = PdfDockStyle.bottom;
    document.template.bottom = footerElement;
  }

  static Future<void> gerarDownload(
    Vistoria vistoria, {
    List<ContentItemPdf>? contentOrder,
    PdfImageResolver? imageResolver,
  }) async {
    final bytes = await gerarBytes(
      vistoria,
      contentOrder: contentOrder,
      imageResolver: imageResolver,
    );
    await gerarDownloadPdf(bytes);
  }

  static Future<void> desenharCabecalho(
    PdfPage page,
    String data,
    String vistoriador,
    String tipo,
  ) async {
    final g = page.graphics;

    // Cores da imagem: azul escuro e verde água
    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final titleFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      16,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    // ================= LOGO =================
    const headerLogoSize = 60.0;
    final ByteData dataLogo = await rootBundle.load('assets/logo.jpg');
    final Uint8List logoBytes = dataLogo.buffer.asUint8List();
    final logo = PdfBitmap(logoBytes);
    g.drawImage(logo, Rect.fromLTWH(0, 0, headerLogoSize, headerLogoSize));



    // ================= EMPRESA =================
    const empresaX = 100.0; // logo 60 + 10
    g.drawString(
      'VISTA SOLUÇÕES EM VISTORIAS',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(empresaX -15, 8, 320, 22),
    );
        final ByteData dataCnpj = await rootBundle.load('assets/cnpj.jpeg');
    final Uint8List cnpjBytes = dataCnpj.buffer.asUint8List();
    final cnpj = PdfBitmap(cnpjBytes);


    
    // Ícone logo.jpg para CNPJ, RUA, Telefone e Email
    const iconSize = 15.0;
    // CNPJ com ícone logo
    final cnpjIconY = 24.0; // Centralizar verticalmente com o texto
    final cnpjIconX = empresaX - 16.0;
    try {
      g.drawImage(cnpj, Rect.fromLTWH(cnpjIconX, cnpjIconY, iconSize, iconSize));
    } catch (_) {
      // Fallback para círculo se houver erro
      const circleRadius = 4.0;
      g.drawEllipse(
        Rect.fromCircle(center: Offset(cnpjIconX + iconSize / 2, cnpjIconY + iconSize / 2), radius: circleRadius),
        brush: brushVerde,
      );
    }
    g.drawString(
      'CNPJ: 57.226.127/0001-40',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(empresaX +4, 25, 300, 18),
    );
    
    // RUA com ícone logo
    final ruaIconY = 40.0;
    final ruaIconX = empresaX - 16.0;


    final ByteData dataMap = await rootBundle.load('assets/map.jpeg');
    final Uint8List mapBytes = dataMap.buffer.asUint8List();
    final map = PdfBitmap(mapBytes);
    try {
      g.drawImage(map, Rect.fromLTWH(ruaIconX, ruaIconY, iconSize, iconSize));
    } catch (_) {
      // Fallback para círculo se houver erro
      const circleRadius = 4.0;
      g.drawEllipse(
        Rect.fromCircle(center: Offset(ruaIconX + iconSize / 2, ruaIconY + iconSize / 2), radius: circleRadius),
        brush: brushVerde,
      );
    }
    g.drawString(
      'RUA 2.850, 310 - BALNEÁRIO CAMBORIÚ/SC',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(empresaX +4, 41, 350, 18),
    );

    // ================= CONTATO =================
    // Telefone com ícone logo
    final telefoneIconY = 24.0 + 2.0;
    final telefoneIconX = 380.0 + _marginLeft - 20.0;


        final ByteData dataWhats = await rootBundle.load('assets/whats.jpeg');
    final Uint8List whatsBytes = dataWhats.buffer.asUint8List();
    final whats = PdfBitmap(whatsBytes);
    try {
      g.drawImage(whats, Rect.fromLTWH(telefoneIconX, telefoneIconY, iconSize -2, iconSize -2));
    } catch (_) {
      // Fallback para círculo se houver erro
      const circleRadius = 4.0;
      g.drawEllipse(
        Rect.fromCircle(center: Offset(telefoneIconX + iconSize / 2, telefoneIconY + iconSize / 2), radius: circleRadius),
        brush: brushVerde,
      );
    }
    g.drawString(
      '(47) 98911-0543',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(380 + _marginLeft, 25, 160, 20),
    );
                final ByteData dataEmail = await rootBundle.load('assets/email.jpeg');
    final Uint8List emailBytes = dataEmail.buffer.asUint8List();
    final email = PdfBitmap(emailBytes);
    
    // Email com ícone logo
    final emailIconY = 40.0;
    final emailIconX = 380.0 + _marginLeft - 22.0;
    try {
      g.drawImage(email, Rect.fromLTWH(emailIconX, emailIconY, iconSize, iconSize));
    } catch (_) {
      // Fallback para círculo se houver erro
      const circleRadius = 4.0;
      g.drawEllipse(
        Rect.fromCircle(center: Offset(emailIconX + iconSize / 2, emailIconY + iconSize / 2), radius: circleRadius),
        brush: brushVerde,
      );
    }
    g.drawString(
      'vistasuavistoria@gmail.com',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(380 + _marginLeft, 41, 200, 20),
    );

    // ================= LINHA VERDE ÁGUA =================
    final pageWidth = page.size.width;
    final penVerde = PdfPen(verdeAgua, width: 1);
    const linhaY = 80.0;
    g.drawLine(penVerde, const Offset(0, linhaY), Offset(pageWidth, linhaY));

    // ================= TÍTULO CENTRAL =================
    g.drawString(
      'VISTORIA IMOBILIÁRIA',
      titleFont,
      brush: brushAzul,
      bounds: Rect.fromLTWH(-40, linhaY + 20, pageWidth, 34),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    // ================= DADOS (DATA | VISTORIADOR | TIPO) =================
    const y = 140.0;
    const dadosLeft = 0.0;

    g.drawString(
      'DATA',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(dadosLeft + _marginLeft, y, 120, 15),
    );
    g.drawString(
      data,
      normal,
      brush: brushPreto,
      bounds: Rect.fromLTWH(dadosLeft + _marginLeft, y + 18, 120, 15),
    );

    g.drawString(
      'VISTORIADOR',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(150 + _marginLeft, y, 150, 15),
    );
    g.drawString(
      vistoriador,
      normal,
      brush: brushPreto,
      bounds: Rect.fromLTWH(150 + _marginLeft, y + 18, 200, 15),
    );

    g.drawString(
      'TIPO',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(450 + _marginLeft, y, 80, 15),
    );
    g.drawString(
      tipo,
      bold,
      brush: brushVerde,
      bounds: Rect.fromLTWH(450 + _marginLeft, y + 18, 80, 15),
    );
  }

  /// Desenha o footer em cada página: logo+texto à esquerda, data/hora central, página e ID à direita.
  static Future<void> desenharFooter(
    PdfPage page, {
    required int pageNumber,
    required int totalPages,
    required DateTime dataHoraGeracao,
    required String idVistoria,
  }) async {
    final g = page.graphics;
    final pageWidth = page.size.width;
    final pageHeight = page.size.height;
    const footerHeight = 50.0;
    final footerY = pageHeight - footerHeight;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final fontPequena = PdfStandardFont(PdfFontFamily.helvetica, 8);
    final fontNormal = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final fontVerde = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final fontVistoria = PdfStandardFont(PdfFontFamily.helvetica, 9, style: PdfFontStyle.bold);

    // ---------- Esquerda: logo + "visto" + "VISTORIA" ----------
    final ByteData dataLogo = await rootBundle.load('assets/logo.jpg');
    final Uint8List logoBytes = dataLogo.buffer.asUint8List();
    final logo = PdfBitmap(logoBytes);
    const logoSize = 60.0;
    g.drawImage(logo, Rect.fromLTWH(0, footerY, logoSize, logoSize));



    // ---------- Centro: data/hora de geração ----------
    final dia = dataHoraGeracao.day.toString().padLeft(2, '0');
    final mes = dataHoraGeracao.month.toString().padLeft(2, '0');
    final ano = dataHoraGeracao.year.toString();
    final hora = dataHoraGeracao.hour.toString().padLeft(2, '0');
    final minuto = dataHoraGeracao.minute.toString().padLeft(2, '0');
    final segundo = dataHoraGeracao.second.toString().padLeft(2, '0');
    final textoGerado = 'Gerado no dia $dia/$mes/$ano às $hora:$minuto:$segundo';

    g.drawString(
      textoGerado,
      fontNormal,
      brush: brushPreto,
      bounds: Rect.fromLTWH(90, footerY + 12, pageWidth - 180, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.center),
    );

    // ---------- Direita: Página X de Y + Vistoria #ID ----------
    final textoPagina = 'Página $pageNumber de $totalPages';
    g.drawString(
      textoPagina,
      fontNormal,
      brush: brushAzul,
      bounds: Rect.fromLTWH(pageWidth - 150, footerY, 130, 14),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    g.drawString(
      'Vistoria: #$idVistoria',
      fontPequena,
      brush: brushPreto,
      bounds: Rect.fromLTWH(pageWidth - 150, footerY + 14, 130, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
  }

  /// Desenha INTRODUÇÃO com paginação (texto, legenda, observações, observação complementar).
  static (PdfPage page, double endY) _desenharIntroducaoComPagina(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required String introducao,
    required List<Legenda> legendas,
    required List<ObservacaoItem> itensObservacao,
    required String observacaoComplementar,
    required String tipoVistoria,
    TipoLegenda? tipoLegenda,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) {
    return desenharIntroducao(
      document,
      page,
      startY: startY,
      introducao: introducao,
      legendas: legendas,
      itensObservacao: itensObservacao,
      observacaoComplementar: observacaoComplementar,
      tipoVistoria: tipoVistoria,
      tipoLegenda: tipoLegenda,
      nomeCustomizado: nomeCustomizado,
      iconBytesCustomizado: iconBytesCustomizado,
    );
  }

  /// Padrão de cabeçalho: ícone + título + linha verde abaixo.
  static void _desenharCabecalhoSecaoPadrao(
    PdfGraphics g,
    double marginX,
    double contentWidth,
    double y,
    PdfPen penVerde,
    PdfStandardFont sectionFont,
    PdfSolidBrush brushAzul, {
    required String titulo,
    required void Function(PdfGraphics g, double iconX, double iconY) drawIcon,
  }) {
    const iconSize = 22.0;
    final iconX = marginX + 4;
    final iconY = y + 2;
    drawIcon(g, iconX, iconY);
    g.drawString(
      titulo.toUpperCase(),
      sectionFont,
      brush: brushAzul,
      bounds: Rect.fromLTWH(marginX + iconSize + 8, y + 4, contentWidth - iconSize - 8, 18),
    );
    // Ícone 22×22 com iconY = y+2 termina em y+24; linha a y+28 deixa ~4px de respiro.
    final lineY = y + 28;
    g.drawLine(penVerde, Offset(marginX, lineY), Offset(marginX + contentWidth, lineY));
  }

  /// Desenha a seção INTRODUÇÃO: ícone documento, título, texto, legenda, observações, observação complementar.
  /// [apenasObservacao] = true desenha só o bloco OBSERVAÇÃO (lista de itens).
  static (PdfPage page, double endY) desenharIntroducao(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required String introducao,
    required List<Legenda> legendas,
    required List<ObservacaoItem> itensObservacao,
    required String observacaoComplementar,
    bool apenasObservacao = false,
    String tipoVistoria = 'ENTRADA',
    TipoLegenda? tipoLegenda,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) {
    var g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    final contentWidth = pageWidth - 2 * marginX;
    const marginDireitaIntro = 75.0;
    final textCorridoWidth = contentWidth - marginDireitaIntro;
    final larguraTextoIntro = textCorridoWidth - _paddingTextoHorizontal;
    final inicioXTexto = marginX + _paddingTextoHorizontal / 2;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final penVerde = PdfPen(verdeAgua, width: 1.5);
    final sectionFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    double y = startY;

    if (!apenasObservacao) {
      // Ícone documento + título + linha
      final titulo = nomeCustomizado ?? 'INTRODUÇÃO';
      _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
        titulo: titulo,
        drawIcon: (g, iconX, iconY) {
          if (iconBytesCustomizado != null && iconBytesCustomizado.isNotEmpty) {
            try {
              final iconBitmap = PdfBitmap(iconBytesCustomizado);
              const iconSize = 22.0;
              g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY, iconSize, iconSize));
            } catch (_) {
              for (var i = 0; i < 3; i++) {
                g.drawLine(penVerde, Offset(iconX + 2, iconY + 4 + i * 5), Offset(iconX + 16, iconY + 4 + i * 5));
              }
            }
          } else {
            for (var i = 0; i < 3; i++) {
              g.drawLine(penVerde, Offset(iconX + 2, iconY + 4 + i * 5), Offset(iconX + 16, iconY + 4 + i * 5));
            }
          }
        },
      );
      y += 40;
    }

    if (apenasObservacao) {
      // Va direto para o bloco OBSERVAÇÃO
      const minAlturaTexto = 50.0;
      if (itensObservacao.isNotEmpty) {
        if (y + 40 > _maxContentY) {
          page = document.pages.add();
          g = page.graphics;
          y = 20.0;
        }
        final tituloObs = apenasObservacao && nomeCustomizado != null ? nomeCustomizado : 'OBSERVAÇÃO';
        _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
          titulo: tituloObs,
          drawIcon: (g, iconX, iconY) {
            if (apenasObservacao && iconBytesCustomizado != null && iconBytesCustomizado.isNotEmpty) {
              try {
                final iconBitmap = PdfBitmap(iconBytesCustomizado);
                const iconSize = 12.0;
                g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY + 2, iconSize, iconSize));
              } catch (_) {
                g.drawEllipse(Rect.fromLTWH(iconX, iconY, 14, 14), pen: penVerde);
                g.drawLine(penVerde, Offset(iconX + 11, iconY + 11), Offset(iconX + 18, iconY + 18));
              }
            } else {
              g.drawEllipse(Rect.fromLTWH(iconX, iconY, 14, 14), pen: penVerde);
              g.drawLine(penVerde, Offset(iconX + 11, iconY + 11), Offset(iconX + 18, iconY + 18));
            }
          },
        );
        y += 40;

        const bulletRadius = 2.0;
        for (final item in itensObservacao) {
          if (item.texto.isEmpty) continue;
          final alturaDisponivel = _maxContentY - y - 35;
          if (alturaDisponivel < minAlturaTexto) {
            page = document.pages.add();
            g = page.graphics;
            y = 20.0;
          }
          final cor = item.rgb;
          final brushCor = PdfSolidBrush(PdfColor(cor.$1, cor.$2, cor.$3));
          g.drawEllipse(
            Rect.fromLTWH(marginX + 4, y + 5, bulletRadius * 2, bulletRadius * 2),
            brush: brushCor,
          );
          final alturaBounds = (_maxContentY - y - 35).clamp(minAlturaTexto, double.infinity);
          final itemResult = PdfTextElement(
            text: item.texto,
            font: normal,
            brush: brushCor,
          ).draw(
            page: page,
            bounds: Rect.fromLTWH(16, y, larguraTextoIntro - (16 - inicioXTexto), alturaBounds),
            format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
          );
          if (itemResult != null) {
            page = itemResult.page;
            g = page.graphics;
            y = itemResult.bounds.bottom + 8;
          } else {
            y += 18;
          }
        }
        y += 8;
      }
      return (page, y);
    }

    // Texto de introdução: largura com padding para não cortar palavras nas bordas
    const minAlturaTexto = 50.0;
    if (introducao.isNotEmpty) {
      var alturaIntro = (_maxContentY - y - 35).clamp(minAlturaTexto, double.infinity);
      if (alturaIntro <= minAlturaTexto && y + 40 > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
        alturaIntro = _maxContentY - y - 35;
      }
      final introResult = PdfTextElement(
        text: introducao,
        font: normal,
        brush: brushPreto,
      ).draw(
        page: page,
        bounds: Rect.fromLTWH(inicioXTexto, y, larguraTextoIntro, alturaIntro),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      if (introResult != null) {
        page = introResult.page;
        g = page.graphics;
        y = introResult.bounds.bottom + 16;
      }
    }

    // LEGENDA
    if (legendas.isNotEmpty) {
      if (y + 40 > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
      }
      // Apenas o texto "LEGENDA" sem ícone e sem linha verde
      g.drawString(
        'LEGENDA:',
        sectionFont,
        brush: brushAzul,
        bounds: Rect.fromLTWH(marginX, y + 2, 200, 18),
      );
      y += 24;

      // Verificar se é ENTRADA (case-insensitive)
      final tipoUpper = tipoVistoria.toUpperCase().trim();
      final isEntrada = tipoUpper == 'ENTRADA' || tipoUpper.contains('ENTRADA');
      
      // Se TipoLegenda for status, título sempre preto (independente de ENTRADA/SAÍDA)
      final isTipoStatus = tipoLegenda == TipoLegenda.status;
      
      for (final leg in legendas) {
        if (y + 30 > _maxContentY) {
          page = document.pages.add();
          g = page.graphics;
          y = 20.0;
        }
        if (leg.valor.isNotEmpty) {
          if (y + 16 > _maxContentY) {
            page = document.pages.add();
            g = page.graphics;
            y = 20.0;
          }
          final cor = leg.rgb;
          final brushCor = PdfSolidBrush(PdfColor(cor.$1, cor.$2, cor.$3));
          
          // Determinar qual brush usar para o texto do título
          // Se TipoLegenda.status: sempre preto
          // Se não for status: preto para ENTRADA, colorido para SAÍDA
          final brushTitulo = isTipoStatus ? brushPreto : (isEntrada ? brushPreto : brushCor);
          
          // Círculo + título na mesma linha (mais próximos, alinhados pela base)
          const circleRadius = 6.0;
          const rowHeight = 16.0;
          const circleX = marginX + 2;
          final rowBottom = y + rowHeight;
          final circleCenter = Offset(circleX + circleRadius, rowBottom - circleRadius);
          final labelLegenda = '${leg.valor}:';
          final titleWidth = bold.measureString(labelLegenda).width;
          const gapCircleTitle = 4.0;
          final textX = circleX + circleRadius * 2 + gapCircleTitle;
          final titleBounds = Rect.fromLTWH(textX, rowBottom - 14, titleWidth, 14);
          final formatTituloBase = PdfStringFormat(lineAlignment: PdfVerticalAlignment.bottom);

          if (isTipoStatus) {
            g.drawEllipse(Rect.fromCircle(center: circleCenter, radius: circleRadius), brush: brushCor);
            g.drawString(labelLegenda, bold, brush: brushPreto, bounds: titleBounds, format: formatTituloBase);
          } else if (isEntrada) {
            g.drawEllipse(Rect.fromCircle(center: circleCenter, radius: circleRadius), brush: brushCor);
            g.drawString(labelLegenda, bold, brush: brushPreto, bounds: titleBounds, format: formatTituloBase);
          } else {
            g.drawString(labelLegenda, bold, brush: brushCor, bounds: Rect.fromLTWH(marginX, rowBottom - 14, titleWidth, 14), format: formatTituloBase);
          }

          y += 16; // Fim da linha do círculo + título

          if (leg.texto.isNotEmpty) {
            final alturaDesc = (_maxContentY - y - 20).clamp(14.0, double.infinity);
            final descResult = PdfTextElement(
              text: leg.texto,
              font: normal,
              brush: brushPreto,
            ).draw(
              page: page,
              bounds: Rect.fromLTWH(inicioXTexto, y, larguraTextoIntro, alturaDesc),
              format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
            );
            if (descResult != null) {
              page = descResult.page;
              g = page.graphics;
              y = descResult.bounds.bottom + 8;
            } else {
              y += 16;
            }
          }
        }
      }
      y += 8;
    }

    // OBSERVAÇÃO COMPLEMENTAR (dentro da Introdução, após Legenda)
    if (observacaoComplementar.isNotEmpty) {
      if (y + 40 > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
      }
      // Apenas o texto "OBSERVAÇÃO COMPLEMENTAR" sem ícone e sem linha verde
      g.drawString(
        'OBSERVAÇÃO COMPLEMENTAR:',
        sectionFont,
        brush: brushAzul,
        bounds: Rect.fromLTWH(marginX, y + 2, 200, 18),
      );
      y += 24;

      var alturaObs = (_maxContentY - y - 35).clamp(minAlturaTexto, double.infinity);
      if (alturaObs <= minAlturaTexto && y + 40 > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
        alturaObs = _maxContentY - y - 35;
      }
      final obsResult = PdfTextElement(
        text: observacaoComplementar,
        font: normal,
        brush: brushPreto,
      ).draw(
        page: page,
        bounds: Rect.fromLTWH(inicioXTexto, y, larguraTextoIntro, alturaObs),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      if (obsResult != null) {
        page = obsResult.page;
        y = obsResult.bounds.bottom + 16;
      }
    }

    // OBSERVAÇÃO não é mais desenhada aqui quando apenasObservacao = false
    // Ela é desenhada apenas quando apenasObservacao = true (seção separada)
    // Isso evita duplicação quando há uma seção de Observação separada (sectionId 4)

    return (page, y);
  }

  /// Desenha seção genérica (INCONFORMIDADES, CHAVES, AMBIENTES, MEDIDORES).
  static (PdfPage page, double endY) _desenharSecaoDados(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required String titulo,
    required List<DadosSubtopico> dados,
    _ModoSecaoPdf modo = _ModoSecaoPdf.padrao,
    Uint8List? iconBytes,
    List<Legenda> legendas = const [],
    required Map<String, Uint8List?> resolvedImageBytes,
  }) {
    var g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    final contentWidth = pageWidth - 2 * marginX;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);
    final vermelho = PdfColor(255, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);
    final brushVermelho = PdfSolidBrush(vermelho);

    final penVerde = PdfPen(verdeAgua, width: 1.5);
    final sectionFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final bold = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    const imgSize = 160.0;
    const imgGap = 8.0;
    const imagensPerLine = 3;

    double y = startY;

    if (y + 50 > _maxContentY) {
      page = document.pages.add();
      g = page.graphics;
      y = 20.0;
    }

    const iconSize = 22.0;
    if (iconBytes != null && iconBytes.isNotEmpty) {
      _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
        titulo: titulo,
        drawIcon: (g, iconX, iconY) {
          try {
            final iconBitmap = PdfBitmap(iconBytes);
            g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY, iconSize, iconSize));
          } catch (_) {
            g.drawEllipse(Rect.fromLTWH(iconX, iconY, iconSize, iconSize), pen: penVerde);
          }
        },
      );
    } else {
      _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
        titulo: titulo,
        drawIcon: (g, iconX, iconY) {
          g.drawEllipse(Rect.fromLTWH(iconX, iconY, iconSize, iconSize), pen: penVerde);
        },
      );
    }
    y += 40;

    // Modo imagens: renderizar apenas imagens sem subtópicos
    if (modo == _ModoSecaoPdf.imagens) {
      // No modo imagens, usar o primeiro subtópico (que contém apenas imagens)
      if (dados.isNotEmpty) {
        final sub = dados[0];
        if (sub.imagens.isNotEmpty) {
          const imgSize = 160.0;
          const imgGap = 8.0;
          const imagensPerLine = 3;
          
          for (var j = 0; j < sub.imagens.length; j += imagensPerLine) {
            final chunk = sub.imagens.skip(j).take(imagensPerLine).toList();
            var x = marginX;

            if (y + imgSize + 50 > _maxContentY) {
              page = document.pages.add();
              g = page.graphics;
              y = 20.0;
            }

            for (final img in chunk) {
              try {
                final raw = _bytesForDadosImagem(img, resolvedImageBytes);
                if (raw != null && raw.isNotEmpty) {
                  final bitmap = PdfBitmap(raw);
                  g.drawImage(bitmap, Rect.fromLTWH(x, y, imgSize, imgSize));
                }
              } catch (_) {}
              x += imgSize + imgGap;
            }
            y += imgSize + 6;

            // Desenhar títulos das imagens
            var xLegend = marginX;
            for (final img in chunk) {
              final textoWidth = normal.measureString(img.legenda).width;
              final textoX = xLegend + (imgSize - textoWidth) / 2;
              g.drawString(
                img.legenda,
                normal,
                brush: brushPreto,
                bounds: Rect.fromLTWH(textoX, y, textoWidth, 12),
              );
              xLegend += imgSize + imgGap;
            }
            y += 14;

            // Desenhar links
            var xLink = marginX;
            for (final img in chunk) {
              if (img.link != null && img.link!.trim().isNotEmpty) {
                var url = img.link!.trim();
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                final linkFont = PdfStandardFont(PdfFontFamily.helvetica, 9);
                final linkText = 'LINK DO VÍDEO';
                final linkWidth = linkFont.measureString(linkText).width;
                final linkX = xLink + (imgSize - linkWidth) / 2;
                
                final linkBrush = PdfSolidBrush(azulEscuro);
                g.drawString(
                  linkText,
                  linkFont,
                  brush: linkBrush,
                  bounds: Rect.fromLTWH(linkX, y - 2, linkWidth, 12),
                );
                
                // Adicionar link clicável
                final linkAnnotation = PdfUriAnnotation(
                  bounds: Rect.fromLTWH(linkX, y - 2, linkWidth, 12),
                  uri: url,
                );
                page.annotations.add(linkAnnotation);
              }
              xLink += imgSize + imgGap;
            }
            y += 16;
          }
        }
      }
      return (page, y);
    }

    // Modos normais: renderizar subtópicos e itens
    for (var topicoIndex = 0; topicoIndex < dados.length; topicoIndex++) {
      final sub = dados[topicoIndex];
      if (sub.nome.isEmpty && sub.itens.isEmpty && (modo != _ModoSecaoPdf.detalhado || sub.imagens.isEmpty)) continue;

      if (y + 30 > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
      }

      // No modo detalhado, mostrar numeração do tópico; em medidores, se nome vazio usar a Identificação do medidor do primeiro item
      String nomeTopico;
      if (modo == _ModoSecaoPdf.detalhado) {
        nomeTopico = '${topicoIndex + 1}. ${sub.nome.toUpperCase()}';
      } else if (modo == _ModoSecaoPdf.medidores && sub.nome.trim().isEmpty) {
        final primeiraIdentificacao = sub.itens.isNotEmpty && sub.itens.first.descricao.trim().isNotEmpty
            ? sub.itens.first.descricao.trim().toUpperCase()
            : 'Medidor ${topicoIndex + 1}';
        nomeTopico = primeiraIdentificacao;
      } else {
        nomeTopico = sub.nome.toUpperCase();
      }
      
      // Tópico (ex: 1. SALA): fonte 12pt
      final tituloFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
      // Subtópico no detalhado (ex: 1.1 PORTA): fonte menor que o tópico
      final itemDetalhadoFont = PdfStandardFont(PdfFontFamily.helvetica, 10, style: PdfFontStyle.bold);
      
      g.drawEllipse(Rect.fromLTWH(marginX + 2, y + 4, 4, 4), brush: brushPreto);
      g.drawString(
        '$nomeTopico:',
        tituloFont,
        brush: brushAzul,
        bounds: Rect.fromLTWH(marginX + 12, y, contentWidth - 12, 18),
      );
      y += 20;

      for (var i = 0; i < sub.itens.length; i++) {
        final item = sub.itens[i];
        final temLeituraOuData = (item.leitura != null && item.leitura!.trim().isNotEmpty) ||
            (item.dataLeitura != null && item.dataLeitura!.trim().isNotEmpty);
        final vazio = item.descricao.isEmpty && item.imagens.isEmpty;
        if (modo == _ModoSecaoPdf.medidores) {
          if (item.descricao.isEmpty && item.imagens.isEmpty && !temLeituraOuData) continue;
        } else if (vazio) {
          continue;
        }

        if (y + 20 > _maxContentY) {
          page = document.pages.add();
          g = page.graphics;
          y = 20.0;
        }

        // Montar linha de texto: em medidores pode ser só leitura/data mesmo sem identificação
        String? linha;
        if (modo == _ModoSecaoPdf.detalhado) {
          linha = '${topicoIndex + 1}.${i + 1} ${item.descricao}';
        } else if (modo == _ModoSecaoPdf.medidores) {
          // Identificação do medidor fica só no título; aqui só o valor da leitura (sem o texto "Leitura")
          final valorLeitura = (item.leitura != null && item.leitura!.trim().isNotEmpty)
              ? item.leitura!.trim()
              : '';
          linha = '${i + 1}. $valorLeitura'.trim();
          if (linha == '${i + 1}.') linha = null; // nada a exibir além do número
        } else if (item.descricao.isNotEmpty) {
          linha = '${i + 1}. ${item.descricao}';
          if (modo == _ModoSecaoPdf.ambientes && item.status != null && item.status!.isNotEmpty) {
            linha += ': ${item.status}';
            if (item.observacao != null && item.observacao!.isNotEmpty) {
              linha += '; ${item.observacao}';
            }
          }
        }

        if (linha != null && linha.isNotEmpty) {
          if (modo == _ModoSecaoPdf.detalhado) {
            // No modo detalhado, o nome do dado deve ser em cor primária e tamanho de título
            if (y + 20 > _maxContentY) {
              page = document.pages.add();
              g = page.graphics;
              y = 20.0;
            }
            // Desenhar o nome do dado (ex: 1.1 PORTA) em cor primária, fonte menor que o tópico (1. SALA)
            g.drawString(
              linha,
              itemDetalhadoFont,
              brush: brushAzul,
              bounds: Rect.fromLTWH(marginX + 12, y, contentWidth - 12, 18),
            );
            y += 20;
            
            // No modo detalhado: legenda e informações adicionais na mesma linha (fluxo horizontal)
            var linhaY = y;
            var linhaX = marginX + 12;
            const lineHeightDetalhado = 14.0;
            const espacoEntreCampos = 8.0;

            if (item.legendaValor != null && item.legendaValor!.isNotEmpty) {
              if (linhaY + lineHeightDetalhado > _maxContentY) {
                page = document.pages.add();
                g = page.graphics;
                linhaY = 20.0;
                linhaX = marginX + 12;
              }
              final legendaTexto = '${item.legendaValor!};';
              final legendaEncontrada = legendas.firstWhere(
                (l) => l.valor == item.legendaValor!,
                orElse: () => Legenda(valor: item.legendaValor!, cor: const Color(0xFF808080), texto: ''),
              );
              final circleSize = 8.0;
              final circleX = linhaX;
              final circleY = linhaY + 3;
              final brushLegenda = PdfSolidBrush(_colorToPdfColor(legendaEncontrada.cor));
              g.drawEllipse(
                Rect.fromLTWH(circleX, circleY, circleSize, circleSize),
                brush: brushLegenda,
              );
              final legendaTextWidth = normal.measureString(legendaTexto).width;
              g.drawString(
                legendaTexto,
                normal,
                brush: brushPreto,
                bounds: Rect.fromLTWH(circleX + circleSize + 6, linhaY, legendaTextWidth, 14),
              );
              linhaX = circleX + circleSize + 6 + legendaTextWidth + espacoEntreCampos;
            }

            if (item.informacoes.isNotEmpty) {
              for (final info in item.informacoes) {
                if (linhaY + lineHeightDetalhado > _maxContentY) {
                  page = document.pages.add();
                  g = page.graphics;
                  linhaY = 20.0;
                  linhaX = marginX + 12;
                }
                final limiteDireito = page.size.width - marginX;
                final nomeTexto = '${info.nome}: ';
                final valorTexto = '${info.valor};';
                final nomeWidth = bold.measureString(nomeTexto).width;
                final valorWidth = normal.measureString(valorTexto).width;
                final totalInfoWidth = nomeWidth + valorWidth + espacoEntreCampos;
                // Se nome+valor não couber na linha (evita cortar texto tipo "BRANCA" em "BRA"), os dois vão para a próxima
                final espacoDisponivel = limiteDireito - linhaX;
                if (nomeWidth + valorWidth > espacoDisponivel) {
                  linhaY += lineHeightDetalhado;
                  linhaX = marginX + 12;
                  if (linhaY + lineHeightDetalhado > _maxContentY) {
                    page = document.pages.add();
                    g = page.graphics;
                    linhaY = 20.0;
                    linhaX = marginX + 12;
                  }
                }
                final valorX = linhaX + nomeWidth;
                g.drawString(nomeTexto, bold, brush: brushPreto, bounds: Rect.fromLTWH(linhaX, linhaY, nomeWidth, 14));
                g.drawString(valorTexto, normal, brush: brushPreto, bounds: Rect.fromLTWH(valorX, linhaY, valorWidth, 14));
                linhaX += totalInfoWidth;
              }
            }

            final desenhouLegendaOuInfo = (item.legendaValor != null && item.legendaValor!.isNotEmpty) || item.informacoes.isNotEmpty;
            if (desenhouLegendaOuInfo) y = linhaY + lineHeightDetalhado;
          } else {
            // Modos não detalhados: comportamento original
            // Calcular altura necessária para o texto (pode ter múltiplas linhas)
            final lines = linha.split('\n');
            final lineHeight = 14.0;
            
            for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
              if (y + lineHeight > _maxContentY) {
                page = document.pages.add();
                g = page.graphics;
                y = 20.0;
              }
              g.drawString(
                lines[lineIndex],
                normal,
                brush: brushPreto,
                bounds: Rect.fromLTWH(marginX + 12, y, contentWidth - 12, lineHeight),
              );
              y += lineHeight;
            }
          }
        }

        // No modo detalhado, as imagens serão desenhadas após todos os dados do tópico
        // Para outros modos, desenhar imagens normalmente após cada item
        if (modo != _ModoSecaoPdf.detalhado && item.imagens.isNotEmpty) {
          for (var j = 0; j < item.imagens.length; j += imagensPerLine) {
            final chunk = item.imagens.skip(j).take(imagensPerLine).toList();
            var x = marginX;

            if (y + imgSize + 50 > _maxContentY) {
              page = document.pages.add();
              g = page.graphics;
              y = 20.0;
            }

            for (final img in chunk) {
              try {
                final raw = _bytesForDadosImagem(img, resolvedImageBytes);
                if (raw != null && raw.isNotEmpty) {
                  final bitmap = PdfBitmap(raw);
                  g.drawImage(bitmap, Rect.fromLTWH(x, y, imgSize, imgSize));
                }
              } catch (_) {}
              x += imgSize + imgGap;
            }
            y += imgSize + 6;

            var xLegend = marginX;
            for (var imgIdx = 0; imgIdx < chunk.length; imgIdx++) {
              final img = chunk[imgIdx];
              // Centralizar texto para modos não detalhados
              final textoWidth = normal.measureString(img.legenda).width;
              final textoX = xLegend + (imgSize - textoWidth) / 2;
              g.drawString(
                img.legenda,
                normal,
                brush: brushPreto,
                bounds: Rect.fromLTWH(textoX, y, textoWidth, 12),
              );
              xLegend += imgSize + imgGap;
            }
            y += 14;

            var xLink = marginX;
            for (final img in chunk) {
              if (img.link != null && img.link!.trim().isNotEmpty) {
                var url = img.link!.trim();
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                // Medir o texto para centralizar
                final linkFont = PdfStandardFont(PdfFontFamily.helvetica, 9, );
                final linkText = 'LINK DO VÍDEO';
                final linkWidth = linkFont.measureString(linkText).width;
                final linkX = xLink + (imgSize - linkWidth) / 2;
                
                PdfTextWebLink(
                  url: url,
                  text: linkText,
                  font: linkFont,
                  brush: brushAzul,
                  pen: PdfPen(azulEscuro),
                ).draw(page, Offset(linkX, y - 2));
              }
              xLink += imgSize + imgGap;
            }
            y += 16;
          }
        }
      }
      
      // No modo detalhado, desenhar todas as imagens do tópico após todos os dados
      if (modo == _ModoSecaoPdf.detalhado) {
        // Coletar todas as imagens de todos os itens do tópico
        final todasImagens = <({DadosImagem img, int itemIndex})>[];
        for (var itemIdx = 0; itemIdx < sub.itens.length; itemIdx++) {
          final itemImg = sub.itens[itemIdx];
          for (final img in itemImg.imagens) {
            todasImagens.add((img: img, itemIndex: itemIdx));
          }
        }
        
        if (todasImagens.isNotEmpty) {
          for (var j = 0; j < todasImagens.length; j += imagensPerLine) {
            final chunk = todasImagens.skip(j).take(imagensPerLine).toList();
            var x = marginX;

            if (y + imgSize + 50 > _maxContentY) {
              page = document.pages.add();
              g = page.graphics;
              y = 20.0;
            }

            for (final entry in chunk) {
              try {
                final raw = _bytesForDadosImagem(entry.img, resolvedImageBytes);
                if (raw != null && raw.isNotEmpty) {
                  final bitmap = PdfBitmap(raw);
                  g.drawImage(bitmap, Rect.fromLTWH(x, y, imgSize, imgSize));
                }
              } catch (_) {}
              x += imgSize + imgGap;
            }
            y += imgSize + 6;

            var xLegend = marginX;
            for (var imgIdx = 0; imgIdx < chunk.length; imgIdx++) {
              final entry = chunk[imgIdx];
              final itemImg = sub.itens[entry.itemIndex];
              // Usar o item correspondente para obter o número
              final numero = '${topicoIndex + 1}.${entry.itemIndex + 1}';
              final nome = itemImg.descricao;
              
              // Medir o tamanho do texto completo para centralizar
              final numeroWidth = bold.measureString(numero).width;
              final nomeWidth = nome.isNotEmpty ? normal.measureString(' $nome').width : 0.0;
              final textoCompletoWidth = numeroWidth + nomeWidth;
              
              // Calcular posição X para centralizar o texto
              final textoX = xLegend + (imgSize - textoCompletoWidth) / 2;
              
              // Desenhar número em negrito
              g.drawString(
                numero,
                bold,
                brush: brushPreto,
                bounds: Rect.fromLTWH(textoX, y, numeroWidth, 12),
              );
              
              // Desenhar nome em normal
              if (nome.isNotEmpty) {
                g.drawString(
                  ' $nome',
                  normal,
                  brush: brushPreto,
                  bounds: Rect.fromLTWH(textoX + numeroWidth, y, nomeWidth, 12),
                );
              }
              xLegend += imgSize + imgGap;
            }
            y += 14;

            var xLink = marginX;
            for (final entry in chunk) {
              final img = entry.img;
              if (img.link != null && img.link!.trim().isNotEmpty) {
                var url = img.link!.trim();
                if (!url.startsWith('http://') && !url.startsWith('https://')) {
                  url = 'https://$url';
                }
                // Medir o texto para centralizar
                final linkFont = PdfStandardFont(PdfFontFamily.helvetica, 9, );
                final linkText = 'LINK DO VÍDEO';
                final linkWidth = linkFont.measureString(linkText).width;
                final linkX = xLink + (imgSize - linkWidth) / 2;
                
                PdfTextWebLink(
                  url: url,
                  text: linkText,
                  font: linkFont,
                  brush: brushAzul,
                  pen: PdfPen(azulEscuro),
                ).draw(page, Offset(linkX, y - 2));
              }
              xLink += imgSize + imgGap;
            }
            y += 16;
          }
        }
      }
    }

    return (page, y);
  }

  /// Desenha ASSINATURAS: logo, título, linha verde, grid de assinaturas (máx 2 por linha).
  static Future<(PdfPage page, double endY)> _desenharAssinaturas(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required List<Assinatura> assinaturas,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) async {
    if (assinaturas.isEmpty) return (page, startY);

    var g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    final contentWidth = pageWidth - 2 * marginX;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushPreto = PdfSolidBrush(preto);

    final penVerde = PdfPen(verdeAgua, width: 1.5);
    final penPreto = PdfPen(preto, width: 1);
    final sectionFont = PdfStandardFont(PdfFontFamily.helvetica, 12, style: PdfFontStyle.bold);
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    const assinaturasPerLine = 2;
    const blockWidth = 250.0;
    const espacoAssinatura = 100.0; // espaço em branco para assinar (acima da linha)
    const blockHeight = 100.0; // espacoAssinatura + linha + titulo + subtitulo + margem
    const blockGap = 20.0;

    double y = startY;

    if (y + 50 > _maxContentY) {
      page = document.pages.add();
      g = page.graphics;
      y = 20.0;
    }

    // Ícone caneta + "ASSINATURAS" + linha
    final tituloAssinaturas = nomeCustomizado ?? 'ASSINATURAS';
    _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
      titulo: tituloAssinaturas,
      drawIcon: (g, iconX, iconY) {
        if (iconBytesCustomizado != null && iconBytesCustomizado.isNotEmpty) {
          try {
            final iconBitmap = PdfBitmap(iconBytesCustomizado);
            const iconSize = 22.0;
            g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY, iconSize, iconSize));
          } catch (_) {
            // Fallback para ícone padrão se houver erro
            g.drawLine(penVerde, Offset(iconX + 2, iconY + 18), Offset(iconX + 16, iconY + 2));
            g.drawLine(penVerde, Offset(iconX + 8, iconY + 10), Offset(iconX + 18, iconY + 6));
          }
        } else {
          // Fallback para ícone padrão se não houver ícone customizado
          g.drawLine(penVerde, Offset(iconX + 2, iconY + 18), Offset(iconX + 16, iconY + 2));
          g.drawLine(penVerde, Offset(iconX + 8, iconY + 10), Offset(iconX + 18, iconY + 6));
        }
      },
    );
    y += 40;

    for (var i = 0; i < assinaturas.length; i += assinaturasPerLine) {
      final chunk = assinaturas.skip(i).take(assinaturasPerLine).toList();

      if (y + blockHeight > _maxContentY) {
        page = document.pages.add();
        g = page.graphics;
        y = 20.0;
      }

      final yRowStart = y;
      var x = marginX;

      for (final a in chunk) {
        if (a.titulo.isEmpty && a.subtitulo.isEmpty) {
          x += blockWidth + blockGap;
          continue;
        }

        // Espaço em branco para assinar (acima da linha)
        final yLinha = yRowStart + espacoAssinatura;
        g.drawLine(penPreto, Offset(x, yLinha), Offset(x + blockWidth, yLinha));
        g.drawString(
          a.titulo.toUpperCase(),
          normal,
          brush: brushPreto,
          bounds: Rect.fromLTWH(x, yLinha + 10, blockWidth, 14),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );
        g.drawString(
          a.subtitulo.toUpperCase(),
          normal,
          brush: brushPreto,
          bounds: Rect.fromLTWH(x, yLinha + 24, blockWidth, 14),
          format: PdfStringFormat(alignment: PdfTextAlignment.center),
        );

        x += blockWidth + blockGap;
      }

      y = yRowStart + blockHeight + 20;
    }

    return (page, y);
  }

  /// Altura aproximada da seção IMÓVEL (sem mapa)
  static const double _alturaImovel = 120.0;

  /// Altura aproximada da seção IMÓVEL com mapa
  /// Cabeçalho (~24) + Dados (~80) + Espaço antes do mapa (12) + Mapa (160) + Espaço após (8) = ~284
  /// Adicionando margem de segurança: 300.0
  static const double _alturaImovelComMapa = 300.0;

  /// Desenha IMÓVEL com paginação: se não couber, cria nova página (com footer via template).
  static (PdfPage page, double endY) _desenharImovelComPagina(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required String identificacao,
    required String endereco,
    required String mobiliado,
    required String quartos,
    required String banheiros,
    Uint8List? mapaBytes,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) {
    final alturaNecessaria = mapaBytes != null ? _alturaImovelComMapa : _alturaImovel;
    if (startY + alturaNecessaria > _maxContentY) {
      page = document.pages.add();
      startY = 20.0;
    }
    final endY = desenharImovel(
      page,
      startY: startY,
      identificacao: identificacao,
      endereco: endereco,
      mobiliado: mobiliado,
      quartos: quartos,
      banheiros: banheiros,
      mapaBytes: mapaBytes,
      nomeCustomizado: nomeCustomizado,
      iconBytesCustomizado: iconBytesCustomizado,
    );
    return (page, endY);
  }

  /// Desenha a seção IMÓVEL: ícone casa+prédio, título verde, linha e dados.
  /// Se mapaBytes for fornecido, desenha a imagem do mapa abaixo dos dados.
  /// Retorna o Y após a seção para continuar o conteúdo abaixo.
  static double desenharImovel(
    PdfPage page, {
    required double startY,
    required String identificacao,
    required String endereco,
    required String mobiliado,
    required String quartos,
    required String banheiros,
    Uint8List? mapaBytes,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) {
    final g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    const lineHeight = 16.0;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final penVerde = PdfPen(verdeAgua, width: 1.5);
    final sectionFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    // ---------- Ícone casa + prédio (contorno verde) ou ícone customizado ----------
    final iconX = marginX;
    final iconY = startY;
    const iconH = 22.0;
    const iconW = 22.0;

    if (iconBytesCustomizado != null && iconBytesCustomizado.isNotEmpty) {
      try {
        final iconBitmap = PdfBitmap(iconBytesCustomizado);
        const iconSize = 22.0;
        g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY, iconSize, iconSize));
      } catch (_) {
        // Fallback para ícone padrão se houver erro
        _desenharIconeImovelPadrao(g, penVerde, iconX, iconY, iconH, iconW);
      }
    } else {
      _desenharIconeImovelPadrao(g, penVerde, iconX, iconY, iconH, iconW);
    }

    // ---------- Título "IMÓVEL" em azul + linha ----------
    final titleX = iconX + iconW + 8;
    final titulo = nomeCustomizado ?? 'IMÓVEL';
    g.drawString(
      titulo.toUpperCase(),
      sectionFont,
      brush: brushAzul,
      bounds: Rect.fromLTWH(titleX - 6, startY + 2, 80, 18),
    );

    final lineY = startY + 24;
    g.drawLine(penVerde, Offset(marginX, lineY), Offset(pageWidth - marginX, lineY));

    // ---------- Lista rótulo: valor (um espaço após o :) ----------
    double rowY = lineY + 10;

    void drawRow(String label, String value) {
      if (value.trim().isEmpty) return;
      final labelTexto = '$label:';
      final labelWidth = bold.measureString(labelTexto).width;
      final valueX = marginX + labelWidth;
      final valueW = (pageWidth - marginX - labelWidth - marginX).clamp(10.0, double.infinity);
      // Valor com um espaço após os dois pontos (desenhado junto para o espaço aparecer)
      final valorComEspaco = ' $value';

      g.drawString(
        labelTexto,
        bold,
        brush: brushAzul,
        bounds: Rect.fromLTWH(marginX, rowY, labelWidth, 14),
      );
      g.drawString(
        valorComEspaco,
        normal,
        brush: brushPreto,
        bounds: Rect.fromLTWH(valueX, rowY, valueW, 14),
      );
      rowY += lineHeight;
    }

    drawRow('IDENTIFICAÇÃO', identificacao);
    drawRow('ENDEREÇO', endereco);
    drawRow('MOBILIADO', mobiliado);
    drawRow('QUARTOS', quartos);
    drawRow('BANHEIROS', banheiros);

    // Mapa do imóvel (opcional) - sempre após os dados
    if (mapaBytes != null && mapaBytes.isNotEmpty) {
      rowY += 12; // Espaço antes do mapa
      try {
        final pdfImage = PdfBitmap(mapaBytes);
        // Usar largura máxima disponível (considerando margens da página)
        // Margens padrão: left=40, right=40 (definidas em gerarBytes)
        const margensPagina = 80.0; // 40 + 40
        final larguraMaxima = pageWidth - margensPagina;
        const mapaHeight = 160.0; // Altura do mapa (dobrada)
        // Calcular escala baseada na largura máxima para manter proporção
        final escala = larguraMaxima / pdfImage.width;
        final drawW = larguraMaxima;
        final drawH = pdfImage.height * escala;
        // Sempre usar largura máxima e altura proporcional
        // IMPORTANTE: limitar a altura de desenho ao mapaHeight para evitar que a imagem
        // seja desenhada além do limite e a próxima seção sobreponha
        final alturaDesenho = drawH > mapaHeight ? mapaHeight : drawH;
        // Desenhar a imagem com altura limitada
        g.drawImage(pdfImage, Rect.fromLTWH(marginX, rowY, drawW, alturaDesenho));
        // Incrementar rowY com a altura real desenhada
        rowY += alturaDesenho + 8;
      } catch (_) {
        // Ignora erro ao desenhar imagem do mapa
      }
    }

    return rowY + 8;
  }

  static void _desenharIconeImovelPadrao(PdfGraphics g, PdfPen penVerde, double iconX, double iconY, double iconH, double iconW) {
    // ========== CASA (esquerda) ==========
    final casaX = iconX + 2;
    final casaY = iconY + 2;
    final casaBaseY = iconY + iconH - 2;
    final casaW = 10.0;
    final casaH = 18.0;
    
    // Casa: telhado (triângulo)
    g.drawLine(penVerde, Offset(casaX, casaBaseY), Offset(casaX + casaW / 2, casaY));
    g.drawLine(penVerde, Offset(casaX + casaW / 2, casaY), Offset(casaX + casaW, casaBaseY));
    g.drawLine(penVerde, Offset(casaX + casaW, casaBaseY), Offset(casaX, casaBaseY));
    
    // Casa: corpo (retângulo)
    g.drawLine(penVerde, Offset(casaX, casaBaseY), Offset(casaX, casaBaseY - casaH));
    g.drawLine(penVerde, Offset(casaX, casaBaseY - casaH), Offset(casaX + casaW, casaBaseY - casaH));
    g.drawLine(penVerde, Offset(casaX + casaW, casaBaseY - casaH), Offset(casaX + casaW, casaBaseY));
    
    // Casa: porta
    final portaX = casaX + 3;
    final portaW = 4.0;
    final portaH = 6.0;
    g.drawLine(penVerde, Offset(portaX, casaBaseY), Offset(portaX, casaBaseY - portaH));
    g.drawLine(penVerde, Offset(portaX, casaBaseY - portaH), Offset(portaX + portaW, casaBaseY - portaH));
    g.drawLine(penVerde, Offset(portaX + portaW, casaBaseY - portaH), Offset(portaX + portaW, casaBaseY));
    
    // Casa: janela
    final janelaCasaX = casaX + 6.5;
    final janelaCasaY = casaBaseY - 12;
    const janelaCasaW = 2.5;
    const janelaCasaH = 2.5;
    g.drawLine(penVerde, Offset(janelaCasaX, janelaCasaY), Offset(janelaCasaX + janelaCasaW, janelaCasaY));
    g.drawLine(penVerde, Offset(janelaCasaX + janelaCasaW, janelaCasaY), Offset(janelaCasaX + janelaCasaW, janelaCasaY + janelaCasaH));
    g.drawLine(penVerde, Offset(janelaCasaX + janelaCasaW, janelaCasaY + janelaCasaH), Offset(janelaCasaX, janelaCasaY + janelaCasaH));
    g.drawLine(penVerde, Offset(janelaCasaX, janelaCasaY + janelaCasaH), Offset(janelaCasaX, janelaCasaY));

    // ========== APARTAMENTO/PRÉDIO (direita) ==========
    final aptX = iconX + 16;
    final aptY = iconY + 2;
    final aptBaseY = iconY + iconH - 2;
    final aptW = 10.0;
    final aptH = 18.0;
    
    // Prédio: contorno (retângulo alto)
    g.drawLine(penVerde, Offset(aptX, aptBaseY), Offset(aptX, aptY));
    g.drawLine(penVerde, Offset(aptX, aptY), Offset(aptX + aptW, aptY));
    g.drawLine(penVerde, Offset(aptX + aptW, aptY), Offset(aptX + aptW, aptBaseY));
    g.drawLine(penVerde, Offset(aptX + aptW, aptBaseY), Offset(aptX, aptBaseY));
    
    // Prédio: divisão de andares (linha horizontal no meio)
    g.drawLine(penVerde, Offset(aptX, aptY + aptH / 2), Offset(aptX + aptW, aptY + aptH / 2));
    
    // Prédio: janelas (2 andares, 2 janelas por andar)
    const janelaW = 3.0;
    const janelaH = 2.5;
    final janelaX1 = aptX + 1.5;
    final janelaX2 = aptX + aptW - janelaW - 1.5;
    final janelaY1 = aptY + 3.0; // Andar superior
    final janelaY2 = aptY + aptH / 2 + 3.0; // Andar inferior
    
    // Janelas andar superior
    for (final jx in [janelaX1, janelaX2]) {
      g.drawLine(penVerde, Offset(jx, janelaY1), Offset(jx + janelaW, janelaY1));
      g.drawLine(penVerde, Offset(jx + janelaW, janelaY1), Offset(jx + janelaW, janelaY1 + janelaH));
      g.drawLine(penVerde, Offset(jx + janelaW, janelaY1 + janelaH), Offset(jx, janelaY1 + janelaH));
      g.drawLine(penVerde, Offset(jx, janelaY1 + janelaH), Offset(jx, janelaY1));
    }
    
    // Janelas andar inferior
    for (final jx in [janelaX1, janelaX2]) {
      g.drawLine(penVerde, Offset(jx, janelaY2), Offset(jx + janelaW, janelaY2));
      g.drawLine(penVerde, Offset(jx + janelaW, janelaY2), Offset(jx + janelaW, janelaY2 + janelaH));
      g.drawLine(penVerde, Offset(jx + janelaW, janelaY2 + janelaH), Offset(jx, janelaY2 + janelaH));
      g.drawLine(penVerde, Offset(jx, janelaY2 + janelaH), Offset(jx, janelaY2));
    }
  }

  /// Altura de uma linha da tabela de pessoas (dados + linha separadora)
  static const double _alturaLinhaPessoa = 26.0;
  /// Altura extra quando a linha tem 2 linhas de texto (NOME/CPF/FUNÇÃO)
  static const double _alturaSegundaLinha = 14.0;

  /// Quebra texto em no máximo 2 linhas que cabem em [maxWidth] com [font].
  static List<String> _quebrarEmMax2Linhas(String texto, PdfFont font, double maxWidth) {
    final t = texto.trim();
    if (t.isEmpty) return [];
    if (font.measureString(t).width <= maxWidth) return [t];
    final words = t.split(RegExp(r'\s+'));
    if (words.isEmpty) return [t];
    String line1 = words.first;
    for (int i = 1; i < words.length; i++) {
      final candidate = '$line1 ${words[i]}';
      if (font.measureString(candidate).width <= maxWidth) {
        line1 = candidate;
      } else {
        break;
      }
    }
    final rest = t.length > line1.length ? t.substring(line1.length).trim() : '';
    if (rest.isEmpty) return [line1];
    if (font.measureString(rest).width <= maxWidth) return [line1, rest];
    String line2 = rest;
    while (line2.length > 1 && font.measureString(line2).width > maxWidth) {
      line2 = line2.substring(0, line2.length - 1);
    }
    return [line1, line2];
  }

  /// Desenha PESSOAS com paginação: ao ultrapassar o footer, cria nova página (com footer via template).
  static (PdfPage page, double endY) _desenharPessoasComPagina(
    PdfDocument document,
    PdfPage page, {
    required double startY,
    required List<Pessoa> pessoas,
    String? nomeCustomizado,
    Uint8List? iconBytesCustomizado,
  }) {
    var g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    const rowHeight = 18.0;
    const headerRowHeight = 20.0;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final penVerde = PdfPen(verdeAgua, width: 1.5);

    final sectionFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    final contentWidth = pageWidth - 2 * marginX;
    final colNomeW = contentWidth * 0.44;
    final colCpfW = contentWidth * 0.22;
    final colFuncaoW = contentWidth * 0.34;
    final colNomeX = marginX;
    final colCpfX = marginX + colNomeW;
    final colFuncaoX = marginX + colNomeW + colCpfW;

    void desenharCabecalhoTabela(double y) {
      final tituloPessoas = nomeCustomizado ?? 'PESSOAS (PARTES)';
      _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, y, penVerde, sectionFont, brushAzul,
        titulo: tituloPessoas,
        drawIcon: (g, iconX, iconY) {
          if (iconBytesCustomizado != null && iconBytesCustomizado.isNotEmpty) {
            try {
              final iconBitmap = PdfBitmap(iconBytesCustomizado);
              const iconSize = 22.0;
              g.drawImage(iconBitmap, Rect.fromLTWH(iconX, iconY, iconSize, iconSize));
            } catch (_) {
              final iconPen = PdfPen(verdeAgua, width: 1.2);
              const r = 4.0;
              for (final c in [
                Offset(iconX + 4, iconY + 10),
                Offset(iconX + 10, iconY + 6),
                Offset(iconX + 16, iconY + 10),
              ]) {
                g.drawEllipse(Rect.fromCircle(center: c, radius: r), pen: iconPen);
              }
              g.drawLine(iconPen, Offset(iconX + 4, iconY + 14), Offset(iconX + 4, iconY + 18));
              g.drawLine(iconPen, Offset(iconX + 10, iconY + 10), Offset(iconX + 10, iconY + 18));
              g.drawLine(iconPen, Offset(iconX + 16, iconY + 14), Offset(iconX + 16, iconY + 18));
            }
          } else {
            final iconPen = PdfPen(verdeAgua, width: 1.2);
            const r = 4.0;
            for (final c in [
              Offset(iconX + 4, iconY + 10),
              Offset(iconX + 10, iconY + 6),
              Offset(iconX + 16, iconY + 10),
            ]) {
              g.drawEllipse(Rect.fromCircle(center: c, radius: r), pen: iconPen);
            }
            g.drawLine(iconPen, Offset(iconX + 4, iconY + 14), Offset(iconX + 4, iconY + 18));
            g.drawLine(iconPen, Offset(iconX + 10, iconY + 10), Offset(iconX + 10, iconY + 18));
            g.drawLine(iconPen, Offset(iconX + 16, iconY + 14), Offset(iconX + 16, iconY + 18));
          }
        },
      );
      final headerY = y + 32;
      g.drawString('NOME', bold, brush: brushAzul,
          bounds: Rect.fromLTWH(colNomeX, headerY, colNomeW, 14));
      g.drawString('CPF/CNPJ', bold, brush: brushAzul,
          bounds: Rect.fromLTWH(colCpfX, headerY, colCpfW, 14));
      g.drawString('FUNÇÃO', bold, brush: brushAzul,
          bounds: Rect.fromLTWH(colFuncaoX, headerY, colFuncaoW, 14));
    }

    double rowY = startY;

    // Desenha o primeiro cabeçalho e linha inicial
    desenharCabecalhoTabela(startY);
    rowY = startY + 32 + 6 + headerRowHeight + 6;

    // Se já não couber na primeira página, inicia em nova
    if (rowY + _alturaLinhaPessoa > _maxContentY) {
      page = document.pages.add();
      g = page.graphics;
      rowY = 20.0;
      desenharCabecalhoTabela(rowY);
      rowY += 32 + 6 + headerRowHeight + 6;
    }

    for (final p in pessoas) {
      if (rowY + _alturaLinhaPessoa > _maxContentY) {
        page = document.pages.add();
        g = page.graphics; // nova página recebe footer automaticamente via template
        rowY = 20.0;
        desenharCabecalhoTabela(rowY);
        rowY += 32 + 6 + headerRowHeight + 6;
      }

      final nomeLinhas = _quebrarEmMax2Linhas(p.nome, normal, colNomeW);
      final cpfLinhas = _quebrarEmMax2Linhas(p.cpfCnpj, normal, colCpfW);
      final funcaoLinhas = _quebrarEmMax2Linhas(p.funcao, normal, colFuncaoW);
      final numLinhas = [nomeLinhas.length, cpfLinhas.length, funcaoLinhas.length].fold(1, (a, b) => a > b ? a : b);

      for (var i = 0; i < nomeLinhas.length; i++) {
        g.drawString(nomeLinhas[i], normal, brush: brushPreto,
            bounds: Rect.fromLTWH(colNomeX, rowY + i * _alturaSegundaLinha, colNomeW, 14));
      }
      for (var i = 0; i < cpfLinhas.length; i++) {
        g.drawString(cpfLinhas[i], normal, brush: brushPreto,
            bounds: Rect.fromLTWH(colCpfX, rowY + i * _alturaSegundaLinha, colCpfW, 14));
      }
      for (var i = 0; i < funcaoLinhas.length; i++) {
        g.drawString(funcaoLinhas[i], normal, brush: brushPreto,
            bounds: Rect.fromLTWH(colFuncaoX, rowY + i * _alturaSegundaLinha, colFuncaoW, 14));
      }

      rowY += (numLinhas > 1 ? numLinhas * _alturaSegundaLinha : rowHeight) + 8;
    }
    return (page, rowY);
  }

  /// Desenha a seção PESSOAS (PARTES): faixa verde com ícone, título, tabela NOME | CPF/CNPJ | FUNÇÃO.
  /// [pessoas] pode ser vazio ou ter quantas linhas quiser.
  static double desenharPessoas(
    PdfPage page, {
    required double startY,
    required List<Pessoa> pessoas,
  }) {
    final g = page.graphics;
    final pageWidth = page.size.width;
    const marginX = 0.0;
    const rowHeight = 18.0;
    const headerRowHeight = 20.0;

    final azulEscuro = _colorToPdfColor(AppColors.primary);
    final verdeAgua = _colorToPdfColor(AppColors.secondary);
    final preto = PdfColor(0, 0, 0);

    final brushAzul = PdfSolidBrush(azulEscuro);
    final brushVerde = PdfSolidBrush(verdeAgua);
    final brushPreto = PdfSolidBrush(preto);

    final penVerde = PdfPen(verdeAgua, width: 1.5);

    final sectionFont = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final bold = PdfStandardFont(
      PdfFontFamily.helvetica,
      10,
      style: PdfFontStyle.bold,
    );
    final normal = PdfStandardFont(PdfFontFamily.helvetica, 10);

    final contentWidth = pageWidth - 2 * marginX;
    // Colunas: NOME 44%; CPF/CNPJ 22%; FUNÇÃO 34%
    final colNomeW = contentWidth * 0.44;
    final colCpfW = contentWidth * 0.22;
    final colFuncaoW = contentWidth * 0.34;
    final colNomeX = marginX;
    final colCpfX = marginX + colNomeW;
    final colFuncaoX = marginX + colNomeW + colCpfW;

    // ---------- Ícone + título + linha ----------
    _desenharCabecalhoSecaoPadrao(g, marginX, contentWidth, startY, penVerde, sectionFont, brushAzul,
      titulo: 'PESSOAS (PARTES)',
      drawIcon: (g, iconX, iconY) {
        final iconPen = PdfPen(verdeAgua, width: 1.2);
        const r = 4.0;
        final centers = [
          Offset(iconX + 4, iconY + 10),
          Offset(iconX + 10, iconY + 6),
          Offset(iconX + 16, iconY + 10),
        ];
        for (final c in centers) {
          g.drawEllipse(Rect.fromCircle(center: c, radius: r), pen: iconPen);
        }
        g.drawLine(iconPen, Offset(iconX + 4, iconY + 14), Offset(iconX + 4, iconY + 18));
        g.drawLine(iconPen, Offset(iconX + 10, iconY + 10), Offset(iconX + 10, iconY + 18));
        g.drawLine(iconPen, Offset(iconX + 16, iconY + 14), Offset(iconX + 16, iconY + 18));
      },
    );

    // ---------- Cabeçalhos da tabela (NOME | CPF/CNPJ | FUNÇÃO) ----------
    final headerY = startY + 32;
    g.drawString(
      'NOME',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(colNomeX, headerY, colNomeW, 14),
    );
    g.drawString(
      'CPF/CNPJ',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(colCpfX, headerY, colCpfW, 14),
    );
    g.drawString(
      'FUNÇÃO',
      bold,
      brush: brushAzul,
      bounds: Rect.fromLTWH(colFuncaoX, headerY, colFuncaoW, 14),
    );

    // ---------- Linhas de dados (máx. 2 linhas por célula: NOME, CPF/CNPJ, FUNÇÃO) ----------
    double rowY = headerY + headerRowHeight + 6;
    for (final p in pessoas) {
      final nomeLinhas = _quebrarEmMax2Linhas(p.nome, normal, colNomeW);
      final cpfLinhas = _quebrarEmMax2Linhas(p.cpfCnpj, normal, colCpfW);
      final funcaoLinhas = _quebrarEmMax2Linhas(p.funcao, normal, colFuncaoW);
      final numLinhas = [nomeLinhas.length, cpfLinhas.length, funcaoLinhas.length].fold(1, (a, b) => a > b ? a : b);

      for (var i = 0; i < nomeLinhas.length; i++) {
        g.drawString(
          nomeLinhas[i],
          normal,
          brush: brushPreto,
          bounds: Rect.fromLTWH(colNomeX, rowY + i * _alturaSegundaLinha, colNomeW, 14),
        );
      }
      for (var i = 0; i < cpfLinhas.length; i++) {
        g.drawString(
          cpfLinhas[i],
          normal,
          brush: brushPreto,
          bounds: Rect.fromLTWH(colCpfX, rowY + i * _alturaSegundaLinha, colCpfW, 14),
        );
      }
      for (var i = 0; i < funcaoLinhas.length; i++) {
        g.drawString(
          funcaoLinhas[i],
          normal,
          brush: brushPreto,
          bounds: Rect.fromLTWH(colFuncaoX, rowY + i * _alturaSegundaLinha, colFuncaoW, 14),
        );
      }
      rowY += (numLinhas > 1 ? numLinhas * _alturaSegundaLinha : rowHeight) + 8;
    }

    return rowY + 8;
  }
}
