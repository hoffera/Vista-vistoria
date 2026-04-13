import 'dart:convert';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';

import '../models/vistoria_salva.dart';
import 'vistoria_document_types.dart';

/// Web: abre JSON pelo seletor de ficheiros; guardar = descarga no browser.
class VistoriaDocumentFileService {
  VistoriaDocumentFileService._();

  static String nomeFicheiroSeguro(String nomeBase) {
    final s = nomeBase.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (s.isEmpty) return 'vistoria.json';
    return s.toLowerCase().endsWith('.json') ? s : '$s.json';
  }

  static Future<String?> salvarVistoriaJson({
    required String json,
    required String nomeFicheiroSugerido,
    String? caminhoExistente,
  }) async {
    final bytes = utf8.encode(json);
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.AnchorElement(href: url)
      ..setAttribute('download', nomeFicheiroSugerido)
      ..click();
    html.Url.revokeObjectUrl(url);
    return null;
  }

  static Future<VistoriaDocumentOpenResult?> abrirEscolhendo() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
      dialogTitle: 'Abrir documento de vistoria',
    );
    if (r == null || r.files.isEmpty) return null;
    final bytes = r.files.first.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final str = utf8.decode(bytes);
    final map = jsonDecode(str) as Map<String, dynamic>;
    final data = VistoriaData.fromJson(map);
    return VistoriaDocumentOpenResult(data: data, caminho: null);
  }
}
