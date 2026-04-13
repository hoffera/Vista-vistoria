import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Sugestão de localização retornada pela busca.
class SugestaoLocalizacao {
  final String displayName;
  final double lat;
  final double lng;

  const SugestaoLocalizacao({
    required this.displayName,
    required this.lat,
    required this.lng,
  });
}

/// Geocoding: Photon (autocomplete) + Nominatim (fallback para coordenadas).
class GeocodingService {
  static const _photonUrl = 'https://photon.komoot.io/api/';
  static const _nominatimUrl = 'https://nominatim.openstreetmap.org';
  static const _userAgent = 'VistoriaApp/1.0';

  /// Busca sugestões em tempo real (estilo Uber) - usa Photon, mais rápido.
  /// [latBias],[lonBias] opcionais para priorizar resultados próximos (ex: -26.99, -48.63 SC).
  static Future<List<SugestaoLocalizacao>> buscarSugestoes(String busca, {double? latBias, double? lonBias}) async {
    final q = busca.trim();
    if (q.length < 2) return [];
    final params = <String, String>{
      'q': q,
      'limit': '8',
      'lang': 'pt',
    };
    if (latBias != null && lonBias != null) {
      params['lat'] = latBias.toString();
      params['lon'] = lonBias.toString();
    }
    final uri = Uri.parse(_photonUrl).replace(queryParameters: params);
    try {
      final resp = await http.get(
        uri,
        headers: {'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return [];
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final features = json['features'] as List? ?? [];
      return features.map((e) {
        final f = e as Map<String, dynamic>;
        final geom = f['geometry'] as Map<String, dynamic>?;
        final coords = geom?['coordinates'] as List? ?? [0.0, 0.0];
        final lon = (coords[0] as num).toDouble();
        final lat = (coords[1] as num).toDouble();
        final props = f['properties'] as Map<String, dynamic>? ?? {};
        final displayName = _montarDisplayName(props);
        return SugestaoLocalizacao(displayName: displayName, lat: lat, lng: lon);
      }).toList();
    } catch (e) {
      // Log do erro para debug, mas retorna lista vazia
      debugPrint('Erro ao buscar sugestões: $e');
      return [];
    }
  }

  static String _montarDisplayName(Map<String, dynamic> props) {
    final parts = <String>[];
    final name = props['name'] as String?;
    final street = props['street'] as String?;
    final housenumber = props['housenumber'] as String?;
    final postcode = props['postcode'] as String?;
    final city = props['city'] as String? ?? props['name'] as String?;
    final state = props['state'] as String?;
    final country = props['country'] as String?;

    if (street != null && street.isNotEmpty) {
      parts.add(housenumber != null ? '$street, $housenumber' : street);
    } else if (name != null && name.isNotEmpty) {
      parts.add(name);
    }
    if (postcode != null && postcode.isNotEmpty) parts.add(postcode);
    if (city != null && city.isNotEmpty && !parts.contains(city)) parts.add(city);
    if (state != null && state.isNotEmpty) parts.add(state);
    if (country != null && country.isNotEmpty) parts.add(country);

    return parts.isEmpty ? 'Localização' : parts.join(', ');
  }

  /// Converte endereço em coordenadas (lat, lng) - tenta Photon primeiro.
  static Future<({double lat, double lng})?> buscarCoordenadas(String endereco) async {
    if (endereco.trim().isEmpty) return null;
    
    // Tenta Photon primeiro
    try {
      final sugestoes = await buscarSugestoes(endereco);
      if (sugestoes.isNotEmpty) {
        return (lat: sugestoes.first.lat, lng: sugestoes.first.lng);
      }
    } catch (e) {
      debugPrint('Erro ao buscar sugestões no Photon: $e');
    }
    
    // Fallback Nominatim
    final uri = Uri.parse('$_nominatimUrl/search').replace(
      queryParameters: {'q': endereco.trim(), 'format': 'json', 'limit': '1'},
    );
    try {
      final resp = await http.get(
        uri,
        headers: {'User-Agent': _userAgent},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        debugPrint('Nominatim retornou status ${resp.statusCode}');
        return null;
      }
      final list = jsonDecode(resp.body) as List;
      if (list.isEmpty) {
        debugPrint('Nominatim retornou lista vazia para: $endereco');
        return null;
      }
      final item = list.first as Map<String, dynamic>;
      // Nominatim retorna lat/lon como String, não como num
      final latStr = item['lat']?.toString() ?? '';
      final lonStr = item['lon']?.toString() ?? '';
      if (latStr.isEmpty || lonStr.isEmpty) {
        debugPrint('Nominatim retornou coordenadas vazias');
        return null;
      }
      final lat = double.tryParse(latStr);
      final lng = double.tryParse(lonStr);
      if (lat == null || lng == null) {
        debugPrint('Erro ao converter coordenadas: lat=$latStr, lng=$lonStr');
        return null;
      }
      return (lat: lat, lng: lng);
    } catch (e) {
      debugPrint('Erro ao buscar coordenadas no Nominatim: $e');
      return null;
    }
  }
}
