import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

import '../models/vistoria_salva.dart';
import 'vistoria_document_types.dart';

/// Grava e abre documentos de vistoria (JSON) no sistema de ficheiros local.
class VistoriaDocumentFileService {
  VistoriaDocumentFileService._();

  static String nomeFicheiroSeguro(String nomeBase) {
    final s = nomeBase.trim().replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (s.isEmpty) return 'vistoria.json';
    return s.toLowerCase().endsWith('.json') ? s : '$s.json';
  }

  /// Guarda JSON: se [caminhoExistente] for válido, sobrescreve; senão abre o diálogo "Guardar como".
  static Future<String?> salvarVistoriaJson({
    required String json,
    required String nomeFicheiroSugerido,
    String? caminhoExistente,
  }) async {
    var target = caminhoExistente;
    if (target == null || target.isEmpty) {
      target = await FilePicker.saveFile(
        dialogTitle: 'Guardar vistoria',
        fileName: nomeFicheiroSugerido,
        type: FileType.custom,
        allowedExtensions: const ['json'],
      );
      if (target == null) return null;
    }
    await File(target).writeAsString(json);
    return target;
  }

  /// Utilizador escolhe um ficheiro .json existente.
  static Future<VistoriaDocumentOpenResult?> abrirEscolhendo() async {
    final r = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
      dialogTitle: 'Abrir documento de vistoria',
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    final str = utf8.decode(bytes);
    final map = jsonDecode(str) as Map<String, dynamic>;
    final data = VistoriaData.fromJson(map);
    final path = f.path;
    return VistoriaDocumentOpenResult(
      data: data,
      caminho: (path != null && path.isNotEmpty) ? path : null,
    );
  }
}
