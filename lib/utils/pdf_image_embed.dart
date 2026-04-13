import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Reduz bytes de imagem antes de [PdfBitmap]: o PDF desenha miniaturas (~160 pt);
/// fotos em 12 MP fazem o motor Syncfusion gastar muita CPU e RAM.
class PdfImageEmbed {
  PdfImageEmbed._();

  /// Miniaturas na secção de dados (caixa ~160×160 pt).
  static const int maxEdgeDadosFoto = 512;

  /// Mapa na ficha do imóvel (largura ~largura útil da página).
  static const int maxEdgeMapa = 960;

  /// Bytes abaixo disto: processa na main isolate (evita overhead do [compute]).
  static const int _isolateThresholdBytes = 120 * 1024;

  static Uint8List? encodeSync(Uint8List? raw, {required int maxEdge, int quality = 82}) {
    if (raw == null || raw.isEmpty) return raw;
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      final w = decoded.width;
      final h = decoded.height;
      if (w <= 0 || h <= 0) return raw;

      img.Image out;
      if (w <= maxEdge && h <= maxEdge) {
        out = decoded;
      } else {
        int nw;
        int nh;
        if (w >= h) {
          nw = maxEdge;
          nh = (h * maxEdge / w).round().clamp(1, 1 << 20);
        } else {
          nh = maxEdge;
          nw = (w * maxEdge / h).round().clamp(1, 1 << 20);
        }
        out = img.copyResize(
          decoded,
          width: nw,
          height: nh,
          interpolation: img.Interpolation.linear,
        );
      }
      return Uint8List.fromList(img.encodeJpg(out, quality: quality));
    } catch (_) {
      return raw;
    }
  }

  static Future<Uint8List?> encodeForDadosFoto(Uint8List? raw) async {
    if (raw == null || raw.isEmpty) return raw;
    if (raw.length < _isolateThresholdBytes) {
      return encodeSync(raw, maxEdge: maxEdgeDadosFoto);
    }
    return compute(_encodeDadosIsolate, raw);
  }

  static Future<Uint8List?> encodeForMapa(Uint8List? raw) async {
    if (raw == null || raw.isEmpty) return raw;
    if (raw.length < _isolateThresholdBytes) {
      return encodeSync(raw, maxEdge: maxEdgeMapa, quality: 85);
    }
    return compute(_encodeMapaIsolate, raw);
  }
}

Uint8List? _encodeDadosIsolate(Uint8List raw) =>
    PdfImageEmbed.encodeSync(raw, maxEdge: PdfImageEmbed.maxEdgeDadosFoto);

Uint8List? _encodeMapaIsolate(Uint8List raw) =>
    PdfImageEmbed.encodeSync(raw, maxEdge: PdfImageEmbed.maxEdgeMapa, quality: 85);
