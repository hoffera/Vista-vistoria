import 'package:flutter/material.dart';

import 'assinatura.dart';
import 'dados.dart';
import 'imovel_data.dart';
import 'legenda.dart';
import 'observacao_item.dart';
import 'pessoa.dart';
import 'vistoria.dart';

/// Metadados de uma vistoria salva
class VistoriaSalva {
  final String id;
  final String nome;
  final DateTime dataCriacao;
  final DateTime dataModificacao;
  final String protocolo;
  final String endereco;
  final String tipo;

  VistoriaSalva({
    required this.id,
    required this.nome,
    required this.dataCriacao,
    required this.dataModificacao,
    required this.protocolo,
    required this.endereco,
    required this.tipo,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'nome': nome,
        'dataCriacao': dataCriacao.toIso8601String(),
        'dataModificacao': dataModificacao.toIso8601String(),
        'protocolo': protocolo,
        'endereco': endereco,
        'tipo': tipo,
      };

  factory VistoriaSalva.fromJson(Map<String, dynamic> json) => VistoriaSalva(
        id: json['id'] as String,
        nome: json['nome'] as String,
        dataCriacao: DateTime.parse(json['dataCriacao'] as String),
        dataModificacao: DateTime.parse(json['dataModificacao'] as String),
        protocolo: json['protocolo'] as String,
        endereco: json['endereco'] as String,
        tipo: json['tipo'] as String,
      );
}

/// Dados completos de uma vistoria para serialização
class VistoriaData {
  final Vistoria vistoria;
  final List<ContentItemPdfData> contentOrder;

  VistoriaData({
    required this.vistoria,
    required this.contentOrder,
  });

  Map<String, dynamic> toJson() => {
        'vistoria': _vistoriaToJson(vistoria),
        'contentOrder': contentOrder.map((e) => e.toJson()).toList(),
      };

  factory VistoriaData.fromJson(Map<String, dynamic> json) => VistoriaData(
        vistoria: _vistoriaFromJson(json['vistoria'] as Map<String, dynamic>),
        contentOrder: (json['contentOrder'] as List)
            .map((e) => ContentItemPdfData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Dados de ContentItemPdf para serialização
class ContentItemPdfData {
  final int sectionId;
  final List<DadosSubtopico>? dadosSecao;
  final List<Assinatura>? assinaturas;
  final ImovelData? imovelData;
  final String? tituloSecaoDados;
  final String? modoSecaoDados;
  final String? iconBytesSecaoDados; // base64
  final String? iconeSecaoDados; // codePoint do ícone da seção de dados
  final String? nomeCustomizado; // Nome customizado da seção
  final String? iconeCustomizado; // Nome do ícone customizado (ex: "Icons.home")

  ContentItemPdfData({
    required this.sectionId,
    this.dadosSecao,
    this.assinaturas,
    this.imovelData,
    this.tituloSecaoDados,
    this.modoSecaoDados,
    this.iconBytesSecaoDados,
    this.iconeSecaoDados,
    this.nomeCustomizado,
    this.iconeCustomizado,
  });

  Map<String, dynamic> toJson() => {
        'sectionId': sectionId,
        if (dadosSecao != null)
          'dadosSecao': dadosSecao!.map((e) => _dadosSubtopicoToJson(e)).toList(),
        if (assinaturas != null)
          'assinaturas': assinaturas!.map((e) => _assinaturaToJson(e)).toList(),
        if (imovelData != null) 'imovelData': _imovelDataToJson(imovelData!),
        if (tituloSecaoDados != null) 'tituloSecaoDados': tituloSecaoDados,
        if (modoSecaoDados != null) 'modoSecaoDados': modoSecaoDados,
        if (iconBytesSecaoDados != null) 'iconBytesSecaoDados': iconBytesSecaoDados,
        if (iconeSecaoDados != null) 'iconeSecaoDados': iconeSecaoDados,
        if (nomeCustomizado != null) 'nomeCustomizado': nomeCustomizado,
        if (iconeCustomizado != null) 'iconeCustomizado': iconeCustomizado,
      };

  factory ContentItemPdfData.fromJson(Map<String, dynamic> json) => ContentItemPdfData(
        sectionId: json['sectionId'] as int,
        dadosSecao: json['dadosSecao'] != null
            ? (json['dadosSecao'] as List)
                .map((e) => _dadosSubtopicoFromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        assinaturas: json['assinaturas'] != null
            ? (json['assinaturas'] as List)
                .map((e) => _assinaturaFromJson(e as Map<String, dynamic>))
                .toList()
            : null,
        imovelData: json['imovelData'] != null
            ? _imovelDataFromJson(json['imovelData'] as Map<String, dynamic>)
            : null,
        tituloSecaoDados: json['tituloSecaoDados'] as String?,
        modoSecaoDados: json['modoSecaoDados'] as String?,
        iconBytesSecaoDados: json['iconBytesSecaoDados'] as String?,
        iconeSecaoDados: json['iconeSecaoDados'] as String?,
        nomeCustomizado: json['nomeCustomizado'] as String?,
        iconeCustomizado: json['iconeCustomizado'] as String?,
      );
}

// Funções auxiliares de serialização

Map<String, dynamic> _vistoriaToJson(Vistoria v) => {
      'nome': v.nome,
      'numero': v.numero,
      'data': v.data,
      'vistoriador': v.vistoriador,
      'tipo': v.tipo,
      'cliente': v.cliente,
      'endereco': v.endereco,
      'protocolo': v.protocolo,
      if (v.mapaLat != null) 'mapaLat': v.mapaLat,
      if (v.mapaLng != null) 'mapaLng': v.mapaLng,
      'observacoes': v.observacoes,
      'mobiliado': v.mobiliado,
      'quartos': v.quartos,
      'banheiros': v.banheiros,
      'introducao': v.introducao,
      'legendas': v.legendas.map((e) => _legendaToJson(e)).toList(),
      if (v.tipoLegenda != null) 'tipoLegenda': v.tipoLegenda!.name,
      'itensObservacao': v.itensObservacao.map((e) => _observacaoItemToJson(e)).toList(),
      'observacaoComplementar': v.observacaoComplementar,
      'inconformidades': v.inconformidades.map((e) => _dadosSubtopicoToJson(e)).toList(),
      'chaves': v.chaves.map((e) => _dadosSubtopicoToJson(e)).toList(),
      'medidores': v.medidores.map((e) => _dadosSubtopicoToJson(e)).toList(),
      'ambientes': v.ambientes.map((e) => _dadosSubtopicoToJson(e)).toList(),
      'assinaturas': v.assinaturas.map((e) => _assinaturaToJson(e)).toList(),
      'pessoas': v.pessoas.map((e) => _pessoaToJson(e)).toList(),
    };

Vistoria _vistoriaFromJson(Map<String, dynamic> json) => Vistoria(
      nome: json['nome'] as String? ?? '',
      numero: json['numero'] as String? ?? '00001',
      data: json['data'] as String,
      vistoriador: json['vistoriador'] as String,
      tipo: json['tipo'] as String,
      cliente: json['cliente'] as String,
      endereco: json['endereco'] as String,
      protocolo: json['protocolo'] as String,
      mapaLat: json['mapaLat'] as double?,
      mapaLng: json['mapaLng'] as double?,
      observacoes: json['observacoes'] as String,
      mobiliado: json['mobiliado'] as String? ?? '',
      quartos: json['quartos'] as String? ?? '',
      banheiros: json['banheiros'] as String? ?? '',
      introducao: json['introducao'] as String? ?? '',
      legendas: (json['legendas'] as List?)
              ?.map((e) => _legendaFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      tipoLegenda: json['tipoLegenda'] != null
          ? TipoLegenda.values.firstWhere(
              (e) => e.name == json['tipoLegenda'],
              orElse: () => TipoLegenda.inconformidade,
            )
          : null,
      itensObservacao: (json['itensObservacao'] as List?)
              ?.map((e) => _observacaoItemFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      observacaoComplementar: json['observacaoComplementar'] as String? ?? '',
      inconformidades: (json['inconformidades'] as List?)
              ?.map((e) => _dadosSubtopicoFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      chaves: (json['chaves'] as List?)
              ?.map((e) => _dadosSubtopicoFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      medidores: (json['medidores'] as List?)
              ?.map((e) => _dadosSubtopicoFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      ambientes: (json['ambientes'] as List?)
              ?.map((e) => _dadosSubtopicoFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      assinaturas: (json['assinaturas'] as List?)
              ?.map((e) => _assinaturaFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      pessoas: (json['pessoas'] as List?)
              ?.map((e) => _pessoaFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _legendaToJson(Legenda l) => {
      'valor': l.valor,
      'cor': l.cor.value,
      'texto': l.texto,
    };

Legenda _legendaFromJson(Map<String, dynamic> json) => Legenda(
      valor: json['valor'] as String,
      cor: Color(json['cor'] as int),
      texto: json['texto'] as String,
    );

Map<String, dynamic> _observacaoItemToJson(ObservacaoItem o) => {
      'texto': o.texto,
      'cor': o.cor.value,
    };

ObservacaoItem _observacaoItemFromJson(Map<String, dynamic> json) => ObservacaoItem(
      texto: json['texto'] as String,
      cor: Color(json['cor'] as int),
    );

Map<String, dynamic> _assinaturaToJson(Assinatura a) => {
      'titulo': a.titulo,
      'subtitulo': a.subtitulo,
    };

Assinatura _assinaturaFromJson(Map<String, dynamic> json) => Assinatura(
      titulo: json['titulo'] as String,
      subtitulo: json['subtitulo'] as String,
    );

Map<String, dynamic> _pessoaToJson(Pessoa p) => {
      'nome': p.nome,
      'cpfCnpj': p.cpfCnpj,
      'funcao': p.funcao,
    };

Pessoa _pessoaFromJson(Map<String, dynamic> json) => Pessoa(
      nome: json['nome'] as String,
      cpfCnpj: json['cpfCnpj'] as String,
      funcao: json['funcao'] as String,
    );

Map<String, dynamic> _dadosSubtopicoToJson(DadosSubtopico d) => {
      'nome': d.nome,
      'itens': d.itens.map((e) => _dadosItemToJson(e)).toList(),
      if (d.imagens.isNotEmpty) 'imagens': d.imagens.map((e) => _dadosImagemToJson(e)).toList(),
    };

DadosSubtopico _dadosSubtopicoFromJson(Map<String, dynamic> json) => DadosSubtopico(
      nome: json['nome'] as String,
      itens: (json['itens'] as List?)
              ?.map((e) => _dadosItemFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      imagens: (json['imagens'] as List?)
              ?.map((e) => _dadosImagemFromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );

Map<String, dynamic> _informacaoAdicionalToJson(InformacaoAdicional info) => {
      'nome': info.nome,
      'valor': info.valor,
    };

InformacaoAdicional _informacaoAdicionalFromJson(Map<String, dynamic> json) => InformacaoAdicional(
      nome: json['nome'] as String,
      valor: json['valor'] as String,
    );

Map<String, dynamic> _dadosItemToJson(DadosItem item) => {
      'descricao': item.descricao,
      'imagens': item.imagens.map((e) => _dadosImagemToJson(e)).toList(),
      if (item.status != null) 'status': item.status,
      if (item.observacao != null) 'observacao': item.observacao,
      if (item.leitura != null) 'leitura': item.leitura,
      if (item.dataLeitura != null) 'dataLeitura': item.dataLeitura,
      if (item.informacoes.isNotEmpty) 'informacoes': item.informacoes.map((e) => _informacaoAdicionalToJson(e)).toList(),
      if (item.legendaValor != null) 'legendaValor': item.legendaValor,
    };

DadosItem _dadosItemFromJson(Map<String, dynamic> json) {
  // Compatibilidade: se informacoes é List<String>, converter para List<InformacaoAdicional>
  final informacoesJson = json['informacoes'] as List?;
  List<InformacaoAdicional> informacoes = [];
  if (informacoesJson != null && informacoesJson.isNotEmpty) {
    final primeiro = informacoesJson.first;
    if (primeiro is String) {
      // Formato antigo: List<String> - ignorar (não há como converter sem perder informação)
      informacoes = [];
    } else if (primeiro is Map) {
      // Formato novo: List<Map>
      informacoes = informacoesJson
          .map((e) => _informacaoAdicionalFromJson(e as Map<String, dynamic>))
          .toList();
    }
  }
  
  return DadosItem(
    descricao: json['descricao'] as String,
    imagens: (json['imagens'] as List?)
            ?.map((e) => _dadosImagemFromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    status: json['status'] as String?,
    observacao: json['observacao'] as String?,
    leitura: json['leitura'] as String?,
    dataLeitura: json['dataLeitura'] as String?,
    informacoes: informacoes,
    legendaValor: json['legendaValor'] as String?,
  );
}

Map<String, dynamic> _dadosImagemToJson(DadosImagem img) => {
      'fonte': img.fonte.name,
      if (img.publicUrl != null) 'publicUrl': img.publicUrl,
      if (img.driveFileId != null) 'driveFileId': img.driveFileId,
      if (img.driveNome != null) 'driveNome': img.driveNome,
      if (img.driveWebViewLink != null) 'driveWebViewLink': img.driveWebViewLink,
      if (img.driveThumbnailLink != null) 'driveThumbnailLink': img.driveThumbnailLink,
      'legenda': img.legenda,
      if (img.link != null) 'link': img.link,
      if (img.dadoRelacionado != null) 'dadoRelacionado': img.dadoRelacionado,
    };

DadosImagem _dadosImagemFromJson(Map<String, dynamic> json) {
  // Migração: JSON antigo com bytes em base64 — imagem não é mais persistida; referência perdida.
  if (json.containsKey('bytes')) {
    return DadosImagem(
      fonte: ImagemFonte.urlPublica,
      legenda: json['legenda'] as String? ?? 'Item',
      link: json['link'] as String?,
      dadoRelacionado: json['dadoRelacionado'] as String?,
    );
  }
  final fonte = ImagemFonte.values.firstWhere(
    (e) => e.name == json['fonte'],
    orElse: () => ImagemFonte.urlPublica,
  );
  return DadosImagem(
    fonte: fonte,
    publicUrl: json['publicUrl'] as String?,
    driveFileId: json['driveFileId'] as String?,
    driveNome: json['driveNome'] as String?,
    driveWebViewLink: json['driveWebViewLink'] as String?,
    driveThumbnailLink: json['driveThumbnailLink'] as String?,
    legenda: json['legenda'] as String? ?? 'Item',
    link: json['link'] as String?,
    dadoRelacionado: json['dadoRelacionado'] as String?,
  );
}

Map<String, dynamic> _imovelDataToJson(ImovelData im) => {
      'protocolo': im.protocolo,
      'endereco': im.endereco,
      'mobiliado': im.mobiliado,
      'quartos': im.quartos,
      'banheiros': im.banheiros,
      'mapaFonte': im.mapaFonte.name,
      if (im.mapaPublicUrl != null) 'mapaPublicUrl': im.mapaPublicUrl,
      if (im.mapaDriveFileId != null) 'mapaDriveFileId': im.mapaDriveFileId,
      if (im.mapaDriveNome != null) 'mapaDriveNome': im.mapaDriveNome,
      if (im.mapaDriveWebViewLink != null) 'mapaDriveWebViewLink': im.mapaDriveWebViewLink,
      if (im.mapaDriveThumbnailLink != null) 'mapaDriveThumbnailLink': im.mapaDriveThumbnailLink,
    };

ImovelData _imovelDataFromJson(Map<String, dynamic> json) {
  MapaImagemFonte fonte = MapaImagemFonte.nenhuma;
  if (json['mapaFonte'] != null) {
    fonte = MapaImagemFonte.values.firstWhere(
      (e) => e.name == json['mapaFonte'],
      orElse: () => MapaImagemFonte.nenhuma,
    );
  } else if (json['mapaBytes'] != null) {
    // Migração: mapa antigo em base64 não é mais carregado
    fonte = MapaImagemFonte.nenhuma;
  }
  return ImovelData(
    protocolo: json['protocolo'] as String? ?? '',
    endereco: json['endereco'] as String? ?? '',
    mobiliado: json['mobiliado'] as String? ?? '',
    quartos: json['quartos'] as String? ?? '',
    banheiros: json['banheiros'] as String? ?? '',
    mapaPublicUrl: json['mapaPublicUrl'] as String?,
    mapaDriveFileId: json['mapaDriveFileId'] as String?,
    mapaDriveNome: json['mapaDriveNome'] as String?,
    mapaDriveWebViewLink: json['mapaDriveWebViewLink'] as String?,
    mapaDriveThumbnailLink: json['mapaDriveThumbnailLink'] as String?,
    mapaFonte: fonte,
  );
}

