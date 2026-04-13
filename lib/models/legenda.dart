import 'package:flutter/material.dart';

/// Tipo de legenda disponível
enum TipoLegenda {
  status, // Legenda com status (NOVO, BOM, REGULAR, NÃO TESTADO, RUIM)
  inconformidade, // Legenda com INCONFORMIDADE
}

/// Legenda com valor (título), cor e texto descritivo.
/// Será utilizada no PDF e em outras partes do documento.
class Legenda {
  final String valor;
  final Color cor;
  final String texto;

  Legenda({
    required this.valor,
    required this.cor,
    required this.texto,
  });

  /// Converte a cor Flutter para componentes RGB (0-255) para uso no PDF.
  (int r, int g, int b) get rgb => (
    (cor.r * 255.0).round().clamp(0, 255),
    (cor.g * 255.0).round().clamp(0, 255),
    (cor.b * 255.0).round().clamp(0, 255),
  );
}
