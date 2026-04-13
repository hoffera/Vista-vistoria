/// Origem da imagem anexada a itens de vistoria.
enum ImagemFonte {
  urlPublica,
  googleDrive,
}

/// Imagem com legenda e link opcional (sem bytes persistidos — apenas referências).
/// Para modo DETALHADO: pode ter referência ao dado relacionado.
class DadosImagem {
  final ImagemFonte fonte;
  final String? publicUrl;
  final String? driveFileId;
  /// Nome do arquivo no Drive (apenas UI).
  final String? driveNome;
  /// Link de visualização no Drive (opcional; útil para exibir/abrir no browser).
  final String? driveWebViewLink;
  /// URL da miniatura devolvida pela API (pode expirar; preview leve sem baixar o ficheiro completo).
  final String? driveThumbnailLink;
  final String legenda;
  final String? link;
  /// Referência ao dado relacionado (DETALHADO): formato "topicoIndex.dadoIndex"
  final String? dadoRelacionado;

  const DadosImagem({
    this.fonte = ImagemFonte.urlPublica,
    this.publicUrl,
    this.driveFileId,
    this.driveNome,
    this.driveWebViewLink,
    this.driveThumbnailLink,
    this.legenda = 'Item',
    this.link,
    this.dadoRelacionado,
  });

  bool get temReferencia =>
      (fonte == ImagemFonte.urlPublica && (publicUrl?.trim().isNotEmpty ?? false)) ||
      (fonte == ImagemFonte.googleDrive && (driveFileId?.trim().isNotEmpty ?? false));
}

/// Informação adicional com nome e valor (DETALHADO).
class InformacaoAdicional {
  final String nome;
  final String valor;

  InformacaoAdicional({
    required this.nome,
    required this.valor,
  });
}

/// Item: descrição + lista de imagens.
class DadosItem {
  final String descricao;
  final List<DadosImagem> imagens;
  final String? status;
  final String? observacao;
  final String? leitura;
  final String? dataLeitura;
  final List<InformacaoAdicional> informacoes;
  final String? legendaValor;

  DadosItem({
    required this.descricao,
    List<DadosImagem>? imagens,
    this.status,
    this.observacao,
    this.leitura,
    this.dataLeitura,
    List<InformacaoAdicional>? informacoes,
    this.legendaValor,
  })  : imagens = imagens ?? [],
        informacoes = informacoes ?? [];
}

/// Subtópico (ex: SALA, COZINHA, SUÍTE).
class DadosSubtopico {
  final String nome;
  final List<DadosItem> itens;
  final List<DadosImagem> imagens;

  DadosSubtopico({
    required this.nome,
    List<DadosItem>? itens,
    List<DadosImagem>? imagens,
  })  : itens = itens ?? [],
        imagens = imagens ?? [];
}
