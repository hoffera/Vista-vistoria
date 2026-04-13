import 'package:flutter/material.dart';

import '../pages/login_page.dart';
import '../pages/welcome_page.dart';
import '../services/auth_service.dart';

/// Mostra [LoginPage] ou [WelcomePage] consoante a sessão guardada.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _aCarregar = true;
  bool _autenticado = false;

  @override
  void initState() {
    super.initState();
    _verificarSessao();
  }

  Future<void> _verificarSessao() async {
    final ok = await AuthService.isLoggedIn();
    if (!mounted) return;
    setState(() {
      _autenticado = ok;
      _aCarregar = false;
    });
  }

  void _aposLogin() {
    setState(() => _autenticado = true);
  }

  Future<void> _sair() async {
    await AuthService.logout();
    if (!mounted) return;
    setState(() => _autenticado = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_aCarregar) {
      return const Scaffold(
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF000080), Color(0xFF00C896)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        ),
      );
    }
    if (!_autenticado) {
      return LoginPage(onSuccess: _aposLogin);
    }
    return WelcomePage(onLogout: _sair);
  }
}
