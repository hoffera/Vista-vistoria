import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Autenticação local: credenciais em [.env] (`APP_LOGIN`, `APP_PASSWORD`) e sessão em [SharedPreferences].
class AuthService {
  AuthService._();

  static const String _keySessao = 'app_auth_sessao_ok';

  static String _usuarioEsperado() => dotenv.env['APP_LOGIN']?.trim() ?? '';

  static String _senhaEsperada() => dotenv.env['APP_PASSWORD']?.trim() ?? '';

  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keySessao) ?? false;
  }

  static Future<void> setLoggedIn(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySessao, value);
  }

  /// Retorna true se utilizador e senha estão corretos; grava sessão.
  /// Falha se `APP_LOGIN` / `APP_PASSWORD` não estiverem definidos no [.env].
  static Future<bool> tryLogin(String usuario, String senha) async {
    final u = _usuarioEsperado();
    final p = _senhaEsperada();
    if (u.isEmpty || p.isEmpty) return false;
    if (usuario.trim() == u && senha == p) {
      await setLoggedIn(true);
      return true;
    }
    return false;
  }

  static Future<void> logout() async {
    await setLoggedIn(false);
  }
}
