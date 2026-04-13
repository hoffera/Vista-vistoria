import 'package:flutter/material.dart';

/// Item de observação com texto e cor.
/// Cada item pode ter uma cor diferente (ex: preto para normal, vermelho para destaque).
class ObservacaoItem {
  final String texto;
  final Color cor;

  ObservacaoItem({
    required this.texto,
    required this.cor,
  });

  /// Converte a cor Flutter para componentes RGB (0-255) para uso no PDF.
  (int r, int g, int b) get rgb => (
    (cor.r * 255.0).round().clamp(0, 255),
    (cor.g * 255.0).round().clamp(0, 255),
    (cor.b * 255.0).round().clamp(0, 255),
  );
}
