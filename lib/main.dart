import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'app/auth_gate.dart';
import 'app/globals.dart';

/// Prioridade: `--dart-define=GOOGLE_OAUTH_CLIENT_ID=...` > ficheiro [.env] >
/// meta tag em web/index.html (lida pelo plugin se [clientId] for null).
String? _resolveGoogleOAuthClientId() {
  const fromDefine = String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID');
  if (fromDefine.trim().isNotEmpty) return fromDefine.trim();

  final a = dotenv.env['GOOGLE_OAUTH_CLIENT_ID']?.trim();
  if (a != null && a.isNotEmpty) return a;

  final b = dotenv.env['ID_CLIENTE_GOOGLE']?.trim();
  if (b != null && b.isNotEmpty) return b;

  return null;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env', isOptional: true);

  await GoogleSignIn.instance.initialize(
    clientId: _resolveGoogleOAuthClientId(),
  );
  appDriveService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF000080),
          secondary: const Color(0xFF00C896),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
