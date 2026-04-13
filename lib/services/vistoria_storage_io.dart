import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/vistoria_salva.dart';

class VistoriaStorageService {
  static const String _vistoriasDir = 'vistorias';
  static const String _metadataFile = 'metadata.json';

  static Future<Directory> _getVistoriasDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final vistoriasDir = Directory('${appDir.path}/$_vistoriasDir');
    if (!await vistoriasDir.exists()) {
      await vistoriasDir.create(recursive: true);
    }
    return vistoriasDir;
  }

  static Future<String> obterProximoNumero() async {
    int maiorNumero = 0;

    final vistoriasDir = await _getVistoriasDirectory();
    if (await vistoriasDir.exists()) {
      await for (final entity in vistoriasDir.list()) {
        if (entity is File && entity.path.endsWith('.json') && !entity.path.endsWith('metadata.json')) {
          try {
            final jsonData = await entity.readAsString();
            final json = jsonDecode(jsonData) as Map<String, dynamic>;
            final vistoriaJson = json['vistoria'] as Map<String, dynamic>?;
            if (vistoriaJson != null) {
              final numeroStr = vistoriaJson['numero'] as String? ?? '';
              if (numeroStr.isNotEmpty) {
                final numeroLimpo = numeroStr.replaceAll(RegExp(r'[^\d]'), '');
                if (numeroLimpo.isNotEmpty) {
                  final num = int.tryParse(numeroLimpo) ?? 0;
                  if (num > maiorNumero) maiorNumero = num;
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    final proximoNumero = maiorNumero + 1;
    return proximoNumero.toString().padLeft(5, '0');
  }

  static Future<void> salvarVistoria({
    required String nome,
    required VistoriaData vistoriaData,
    String? idExistente,
  }) async {
    final vistoriasDir = await _getVistoriasDirectory();
    final id = idExistente ?? const Uuid().v4();
    final agora = DateTime.now();

    final dataFile = File('${vistoriasDir.path}/$id.json');
    final jsonData = jsonEncode(vistoriaData.toJson());
    await dataFile.writeAsString(jsonData);

    final metadata = await _carregarMetadata();
    final vistoriaSalva = VistoriaSalva(
      id: id,
      nome: nome,
      dataCriacao: idExistente != null
          ? metadata.firstWhere((v) => v.id == id, orElse: () => VistoriaSalva(
                id: id,
                nome: nome,
                dataCriacao: agora,
                dataModificacao: agora,
                protocolo: vistoriaData.vistoria.protocolo,
                endereco: vistoriaData.vistoria.endereco,
                tipo: vistoriaData.vistoria.tipo,
              )).dataCriacao
          : agora,
      dataModificacao: agora,
      protocolo: vistoriaData.vistoria.protocolo,
      endereco: vistoriaData.vistoria.endereco,
      tipo: vistoriaData.vistoria.tipo,
    );

    if (idExistente != null) {
      final index = metadata.indexWhere((v) => v.id == id);
      if (index >= 0) {
        metadata[index] = vistoriaSalva;
      } else {
        metadata.add(vistoriaSalva);
      }
    } else {
      metadata.add(vistoriaSalva);
    }

    await _salvarMetadata(metadata);
  }

  static Future<VistoriaData?> carregarVistoria(String id) async {
    try {
      final vistoriasDir = await _getVistoriasDirectory();
      final dataFile = File('${vistoriasDir.path}/$id.json');
      if (!await dataFile.exists()) return null;

      final jsonData = await dataFile.readAsString();
      final json = jsonDecode(jsonData) as Map<String, dynamic>;
      return VistoriaData.fromJson(json);
    } catch (e) {
      return null;
    }
  }

  static Future<List<VistoriaSalva>> listarVistorias() async {
    return _carregarMetadata();
  }

  static Future<bool> deletarVistoria(String id) async {
    try {
      final vistoriasDir = await _getVistoriasDirectory();
      final dataFile = File('${vistoriasDir.path}/$id.json');
      if (await dataFile.exists()) {
        await dataFile.delete();
      }

      final metadata = await _carregarMetadata();
      metadata.removeWhere((v) => v.id == id);
      await _salvarMetadata(metadata);
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<VistoriaSalva>> _carregarMetadata() async {
    try {
      final vistoriasDir = await _getVistoriasDirectory();
      final metadataFile = File('${vistoriasDir.path}/$_metadataFile');
      if (!await metadataFile.exists()) return [];

      final jsonData = await metadataFile.readAsString();
      final json = jsonDecode(jsonData) as List<dynamic>;
      return json.map((e) => VistoriaSalva.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => b.dataModificacao.compareTo(a.dataModificacao));
    } catch (e) {
      return [];
    }
  }

  static Future<void> _salvarMetadata(List<VistoriaSalva> metadata) async {
    final vistoriasDir = await _getVistoriasDirectory();
    final metadataFile = File('${vistoriasDir.path}/$_metadataFile');
    final json = jsonEncode(metadata.map((v) => v.toJson()).toList());
    await metadataFile.writeAsString(json);
  }
}
