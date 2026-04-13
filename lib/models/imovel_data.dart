/// Origem da imagem do mapa do imóvel.
enum MapaImagemFonte {
  nenhuma,
  urlPublica,
  googleDrive,
}

/// Dados do imóvel para uma instância (sem bytes persistidos — apenas referências).
class ImovelData {
  final String protocolo;
  final String endereco;
  final String mobiliado;
  final String quartos;
  final String banheiros;

  /// URL HTTP(S) direta para a imagem do mapa (quando [mapaFonte] == urlPublica).
  final String? mapaPublicUrl;

  /// ID do arquivo no Google Drive (quando [mapaFonte] == googleDrive).
  final String? mapaDriveFileId;

  /// Nome exibido na UI para arquivo do Drive (opcional).
  final String? mapaDriveNome;

  /// Link de visualização no Drive (opcional).
  final String? mapaDriveWebViewLink;

  /// Miniatura API (opcional; pode expirar).
  final String? mapaDriveThumbnailLink;

  final MapaImagemFonte mapaFonte;

  const ImovelData({
    this.protocolo = '',
    this.endereco = '',
    this.mobiliado = '',
    this.quartos = '',
    this.banheiros = '',
    this.mapaPublicUrl,
    this.mapaDriveFileId,
    this.mapaDriveNome,
    this.mapaDriveWebViewLink,
    this.mapaDriveThumbnailLink,
    this.mapaFonte = MapaImagemFonte.nenhuma,
  });

  bool get temMapa =>
      mapaFonte != MapaImagemFonte.nenhuma &&
      ((mapaFonte == MapaImagemFonte.urlPublica && (mapaPublicUrl?.isNotEmpty ?? false)) ||
          (mapaFonte == MapaImagemFonte.googleDrive && (mapaDriveFileId?.isNotEmpty ?? false)));
}
