import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/dados.dart';
import '../models/imovel_data.dart';
import 'google_drive_service.dart';

/// Chave estável para cache de bytes por referência de imagem.
String pdfImageKeyDados(DadosImagem img) =>
    '${img.fonte.name}|${img.publicUrl ?? ''}|${img.driveFileId ?? ''}';

String pdfImageKeyMapa(ImovelData im) =>
    '${im.mapaFonte.name}|${im.mapaPublicUrl ?? ''}|${im.mapaDriveFileId ?? ''}';

/// Resolve referências de imagem (URL pública ou Google Drive) para bytes do PDF.
class PdfImageResolver {
  PdfImageResolver({
    required this.resolveDadosImagem,
    required this.resolveMapa,
  });

  final Future<Uint8List?> Function(DadosImagem img) resolveDadosImagem;
  final Future<Uint8List?> Function(ImovelData imovel) resolveMapa;

  /// GET HTTP simples (URLs públicas). Falha silenciosa retorna null.
  static Future<Uint8List?> fetchHttpUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !uri.hasScheme) return null;
    try {
      final r = await http.get(uri);
      if (r.statusCode >= 200 && r.statusCode < 300) {
        return r.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  /// Implementação padrão usando [GoogleDriveService] opcional.
  factory PdfImageResolver.withDrive(GoogleDriveService? drive) {
    return PdfImageResolver(
      resolveDadosImagem: (img) async {
        if (!img.temReferencia) return null;
        switch (img.fonte) {
          case ImagemFonte.urlPublica:
            final u = img.publicUrl?.trim();
            if (u == null || u.isEmpty) return null;
            return fetchHttpUrl(u);
          case ImagemFonte.googleDrive:
            final id = img.driveFileId?.trim();
            if (id == null || id.isEmpty || drive == null) return null;
            return drive.downloadFileBytes(id);
        }
      },
      resolveMapa: (im) async {
        if (!im.temMapa) return null;
        switch (im.mapaFonte) {
          case MapaImagemFonte.nenhuma:
            return null;
          case MapaImagemFonte.urlPublica:
            final u = im.mapaPublicUrl?.trim();
            if (u == null || u.isEmpty) return null;
            return fetchHttpUrl(u);
          case MapaImagemFonte.googleDrive:
            final id = im.mapaDriveFileId?.trim();
            if (id == null || id.isEmpty || drive == null) return null;
            return drive.downloadFileBytes(id);
        }
      },
    );
  }
}
