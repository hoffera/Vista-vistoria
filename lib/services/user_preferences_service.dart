import 'package:shared_preferences/shared_preferences.dart';

/// Serviço para gerenciar preferências do usuário
class UserPreferencesService {
  static const String _keyVistoriadorPadrao = 'vistoriador_padrao';
  static const String _keyNumeroVistoriaSeq = 'vistoria_numero_seq';

  /// Salva o vistoriador padrão
  static Future<void> salvarVistoriadorPadrao(String vistoriador) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyVistoriadorPadrao, vistoriador);
  }

  /// Obtém o vistoriador padrão salvo
  static Future<String?> obterVistoriadorPadrao() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyVistoriadorPadrao);
  }

  /// Próximo número sugerido (00001, 00002, …) sem depender de ficheiros na app.
  static Future<String> obterProximoNumeroVistoria() async {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(_keyNumeroVistoriaSeq) ?? 0) + 1;
    await prefs.setInt(_keyNumeroVistoriaSeq, n);
    return n.toString().padLeft(5, '0');
  }
}

