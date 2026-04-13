import '../models/vistoria_salva.dart';

/// Resultado de abrir um ficheiro de vistoria (.json).
class VistoriaDocumentOpenResult {
  VistoriaDocumentOpenResult({
    required this.data,
    this.caminho,
  });

  final VistoriaData data;
  /// Caminho absoluto no disco (desktop/mobile). Null na Web ou quando indisponível.
  final String? caminho;
}
