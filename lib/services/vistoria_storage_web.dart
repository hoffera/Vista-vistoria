import 'dart:convert';

import 'package:idb_shim/idb_browser.dart';
import 'package:uuid/uuid.dart';

import '../models/vistoria_salva.dart';

/// Persistência IndexedDB (Web / Wasm) — mesma API que [VistoriaStorageService] em IO.
class VistoriaStorageService {
  static const _dbName = 'vistoria_pdf_db';
  static const _storeKv = 'kv';
  static const _keyMeta = '__metadata__';

  static Database? _database;

  static Future<Database> _db() async {
    if (_database != null) return _database!;
    final factory = getIdbFactory()!;
    _database = await factory.open(
      _dbName,
      version: 1,
      onUpgradeNeeded: (VersionChangeEvent e) {
        final db = e.database;
        if (!db.objectStoreNames.contains(_storeKv)) {
          db.createObjectStore(_storeKv);
        }
      },
    );
    return _database!;
  }

  static Future<ObjectStore> _store(Transaction txn) async => txn.objectStore(_storeKv);

  static Future<String> obterProximoNumero() async {
    int maiorNumero = 0;
    final db = await _db();
    final txn = db.transaction(_storeKv, idbModeReadOnly);
    final store = await _store(txn);
    final keys = await store.getAllKeys();
    for (final key in keys) {
      final k = key.toString();
      if (k == _keyMeta) continue;
      try {
        final raw = await store.getObject(k);
        if (raw == null) continue;
        final str = raw is String ? raw : jsonEncode(raw);
        final json = jsonDecode(str) as Map<String, dynamic>;
        final vistoriaJson = json['vistoria'] as Map<String, dynamic>?;
        if (vistoriaJson != null) {
          final numeroStr = vistoriaJson['numero'] as String? ?? '';
          if (numeroStr.isNotEmpty) {
            final numeroLimpo = numeroStr.replaceAll(RegExp(r'[^\d]'), '');
            if (numeroLimpo.isNotEmpty) {
              final n = int.tryParse(numeroLimpo) ?? 0;
              if (n > maiorNumero) maiorNumero = n;
            }
          }
        }
      } catch (_) {}
    }
    await txn.completed;
    final proximo = maiorNumero + 1;
    return proximo.toString().padLeft(5, '0');
  }

  static Future<void> salvarVistoria({
    required String nome,
    required VistoriaData vistoriaData,
    String? idExistente,
  }) async {
    final db = await _db();
    final id = idExistente ?? const Uuid().v4();
    final agora = DateTime.now();

    final txn = db.transaction(_storeKv, idbModeReadWrite);
    final store = await _store(txn);

    final jsonData = jsonEncode(vistoriaData.toJson());
    await store.put(jsonData, id);

    final metaRaw = await store.getObject(_keyMeta);
    List<VistoriaSalva> metadata = [];
    if (metaRaw != null) {
      try {
        final list = jsonDecode(metaRaw as String) as List<dynamic>;
        metadata = list.map((e) => VistoriaSalva.fromJson(e as Map<String, dynamic>)).toList();
      } catch (_) {}
    }

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

    await store.put(
      jsonEncode(metadata.map((v) => v.toJson()).toList()),
      _keyMeta,
    );
    await txn.completed;
  }

  static Future<VistoriaData?> carregarVistoria(String id) async {
    try {
      final db = await _db();
      final txn = db.transaction(_storeKv, idbModeReadOnly);
      final store = await _store(txn);
      final raw = await store.getObject(id);
      await txn.completed;
      if (raw == null) return null;
      final str = raw is String ? raw : jsonEncode(raw);
      final json = jsonDecode(str) as Map<String, dynamic>;
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
      final db = await _db();
      final txn = db.transaction(_storeKv, idbModeReadWrite);
      final store = await _store(txn);
      await store.delete(id);

      final metaRaw = await store.getObject(_keyMeta);
      List<VistoriaSalva> metadata = [];
      if (metaRaw != null) {
        try {
          final list = jsonDecode(metaRaw as String) as List<dynamic>;
          metadata = list.map((e) => VistoriaSalva.fromJson(e as Map<String, dynamic>)).toList();
        } catch (_) {}
      }
      metadata.removeWhere((v) => v.id == id);
      await store.put(
        jsonEncode(metadata.map((v) => v.toJson()).toList()),
        _keyMeta,
      );
      await txn.completed;
      return true;
    } catch (e) {
      return false;
    }
  }

  static Future<List<VistoriaSalva>> _carregarMetadata() async {
    try {
      final db = await _db();
      final txn = db.transaction(_storeKv, idbModeReadOnly);
      final store = await _store(txn);
      final metaRaw = await store.getObject(_keyMeta);
      await txn.completed;
      if (metaRaw == null) return [];
      final list = jsonDecode(metaRaw as String) as List<dynamic>;
      return list.map((e) => VistoriaSalva.fromJson(e as Map<String, dynamic>)).toList()
        ..sort((a, b) => b.dataModificacao.compareTo(a.dataModificacao));
    } catch (e) {
      return [];
    }
  }
}
