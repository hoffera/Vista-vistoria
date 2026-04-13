import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Gera imagem estática do mapa a partir de lat/lng usando tiles OSM.
class MapaStaticoService {
  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _tileSize = 256;
  static const _zoom = 19; // Zoom maior para mostrar mais detalhes
  static const _gridWidth = 6; // 6 tiles de largura
  static const _gridHeight = 3; // 3 tiles de altura = retângulo mais baixo

  /// Converte lat/lng para coordenadas de tile (x, y) no zoom z.
  static (int x, int y) _latLngToTile(double lat, double lng, int z) {
    final n = math.pow(2, z).toDouble();
    final latRad = lat * math.pi / 180;
    final x = ((lng + 180) / 360 * n).floor();
    final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n).floor();
    return (x, y);
  }

  /// Busca um tile e retorna os bytes da imagem.
  static Future<Uint8List?> _fetchTile(int z, int x, int y) async {
    final url = _tileUrl.replaceAll('{z}', '$z').replaceAll('{x}', '$x').replaceAll('{y}', '$y');
    try {
      final resp = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'VistoriaApp/1.0'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      return resp.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  /// Converte lat/lng para coordenadas de pixel no sistema de tiles.
  static (double x, double y) _latLngToPixel(double lat, double lng, int z) {
    final n = math.pow(2, z).toDouble();
    final latRad = lat * math.pi / 180;
    final x = ((lng + 180) / 360 * n);
    final y = ((1 - math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) / 2 * n);
    return (x * _tileSize, y * _tileSize);
  }

  /// Gera imagem estática do mapa centrada em (lat, lng).
  /// Retorna PNG bytes ou null em caso de erro.
  static Future<Uint8List?> gerarImagem(double lat, double lng) async {
    final (centerTileX, centerTileY) = _latLngToTile(lat, lng, _zoom);
    final offsetX = _gridWidth ~/ 2;
    final offsetY = _gridHeight ~/ 2;
    final startX = centerTileX - offsetX;
    final startY = centerTileY - offsetY;

    final width = _tileSize * _gridWidth;
    final height = _tileSize * _gridHeight;
    final outImage = img.Image(width: width, height: height);

    for (var dy = 0; dy < _gridHeight; dy++) {
      for (var dx = 0; dx < _gridWidth; dx++) {
        final tx = startX + dx;
        final ty = startY + dy;
        final bytes = await _fetchTile(_zoom, tx, ty);
        if (bytes == null) continue;
        final tile = img.decodeImage(bytes);
        if (tile == null) continue;
        img.compositeImage(outImage, tile, dstX: dx * _tileSize, dstY: dy * _tileSize);
      }
    }

    // Calcular posição exata do marcador baseado nas coordenadas lat/lng
    final (pixelX, pixelY) = _latLngToPixel(lat, lng, _zoom);
    // Posição do primeiro tile (startX, startY) na imagem em pixels
    final startPixelX = startX * _tileSize;
    final startPixelY = startY * _tileSize;
    // Posição do marcador na imagem
    final markerX = (pixelX - startPixelX).round();
    final markerY = (pixelY - startPixelY).round();
    
    // Garantir que o marcador está dentro da imagem
    final finalX = markerX.clamp(0, width - 1);
    final finalY = markerY.clamp(0, height - 1);
    
    // Desenhar pin de localização (formato de gota/pin)
    const pinRadius = 10;
    
    // Círculo principal (parte superior do pin)
    img.fillCircle(outImage, x: finalX, y: finalY, radius: pinRadius, color: img.ColorRgba8(255, 0, 0, 255));
    // Círculo interno branco
    img.fillCircle(outImage, x: finalX, y: finalY, radius: pinRadius - 3, color: img.ColorRgba8(255, 255, 255, 255));
    // Ponto central vermelho
    img.fillCircle(outImage, x: finalX, y: finalY, radius: 3, color: img.ColorRgba8(255, 0, 0, 255));
    
    // Ponta do pin (triângulo apontando para baixo)
    final pinTipY = finalY + pinRadius + 2;
    final tipWidth = 6;
    for (var i = 0; i < tipWidth; i++) {
      final startX = finalX - (tipWidth - i);
      final endX = finalX + (tipWidth - i);
      final tipY = pinTipY + i;
      if (tipY < height && startX >= 0 && endX < width) {
        for (var px = startX; px <= endX; px++) {
          if (px >= 0 && px < width && tipY >= 0 && tipY < height) {
            outImage.setPixel(px, tipY, img.ColorRgba8(255, 0, 0, 255));
          }
        }
      }
    }

    final pngBytes = img.encodePng(outImage);
    return Uint8List.fromList(pngBytes);
  }
}
