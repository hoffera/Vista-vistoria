import 'dart:async';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../widgets/gsi_sign_in_button.dart';

/// Escopos para listar e baixar arquivos de imagem do Drive.
const List<String> kGoogleDriveImageScopes = <String>[
  'https://www.googleapis.com/auth/drive.readonly',
];

/// ID especial do Drive v3 para a raiz "Meu Drive".
const String kGoogleDriveRootId = 'root';

const String _folderMime = 'application/vnd.google-apps.folder';

/// Resultado paginado de [GoogleDriveService.listFolderContents].
class DriveFolderListResult {
  const DriveFolderListResult({
    required this.files,
    this.nextPageToken,
  });

  final List<drive.File> files;
  final String? nextPageToken;
}

/// Serviço OAuth + Drive API (listar imagens, baixar bytes).
///
/// Chame [GoogleSignIn.instance.initialize] em `main()` antes de [runApp] e
/// em seguida [init] para sincronizar [account] com os eventos do plugin.
class GoogleDriveService {
  GoogleSignInAccount? _account;
  StreamSubscription<GoogleSignInAuthenticationEvent>? _authSub;

  /// Cache de miniaturas do picker (por id de ficheiro) para evitar pedidos repetidos.
  final Map<String, Future<Uint8List?>> _pickerThumbnailCache =
      <String, Future<Uint8List?>>{};

  /// Cache de downloads completos por ficheiro — evita novo pedido ao dar setState (ex.: preview PDF).
  final Map<String, Future<Uint8List?>> _downloadFileBytesCache =
      <String, Future<Uint8List?>>{};

  /// Após o primeiro sucesso de [hasDriveAccess], evita falsos negativos no web
  /// e novos fluxos de [signIn] ao adicionar imagens.
  bool _driveAccessConfirmed = false;

  GoogleSignInAccount? get account => _account;

  /// Sincroniza [account] com o utilizador atual (ex.: após eventos na UI).
  void setAccount(GoogleSignInAccount? user) {
    _account = user;
  }

  void clearAccount() {
    _account = null;
    _driveAccessConfirmed = false;
    _downloadFileBytesCache.clear();
  }

  /// Marca que o utilizador já passou pelo gate / OAuth com Drive (ex.: tela inicial web).
  void markDriveAccessConfirmed() {
    _driveAccessConfirmed = true;
  }

  /// Indica se já existe sessão com escopo Drive (mesmo que [account] seja null
  /// no web — o plugin pode não expor [GoogleSignInAccount] de imediato).
  Future<bool> hasDriveAccess() async {
    if (_driveAccessConfirmed) return true;
    if (_account != null) {
      _driveAccessConfirmed = true;
      return true;
    }
    try {
      final authz = await GoogleSignIn.instance.authorizationClient
          .authorizationForScopes(kGoogleDriveImageScopes);
      if (authz != null) {
        _driveAccessConfirmed = true;
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Registra o listener de autenticação e tenta login leve (FedCM no web).
  /// Deve ser chamado uma vez após [GoogleSignIn.instance.initialize].
  void init() {
    _authSub?.cancel();
    _authSub = GoogleSignIn.instance.authenticationEvents.listen(
      (event) {
        switch (event) {
          case GoogleSignInAuthenticationEventSignIn(:final user):
            _account = user;
          case GoogleSignInAuthenticationEventSignOut():
            _account = null;
            _driveAccessConfirmed = false;
            _pickerThumbnailCache.clear();
            _downloadFileBytesCache.clear();
        }
      },
      onError: (_) {},
    );
    unawaited(GoogleSignIn.instance.attemptLightweightAuthentication());
  }

  /// No Android/iOS/desktop usa [GoogleSignIn.authenticate]. No web, exibe o
  /// botão GIS ([renderButton]); o login interativo não está disponível via API
  /// única do plugin nessa plataforma.
  Future<GoogleSignInAccount?> signIn(BuildContext context) async {
    if (_driveAccessConfirmed) {
      return _account;
    }
    if (_account != null) return _account;
    if (await hasDriveAccess()) {
      return _account;
    }
    if (GoogleSignIn.instance.supportsAuthenticate()) {
      _account = await GoogleSignIn.instance.authenticate(
        scopeHint: kGoogleDriveImageScopes,
      );
      if (_account != null) {
        _driveAccessConfirmed = true;
      }
      return _account;
    }
    return showDialog<GoogleSignInAccount>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _WebDriveSignInDialog(),
    );
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.signOut();
    _account = null;
    _driveAccessConfirmed = false;
    _pickerThumbnailCache.clear();
    _downloadFileBytesCache.clear();
  }

  /// Bytes da miniatura para o seletor. [Image.network] com [File.thumbnailLink]
  /// falha no web (sem OAuth). Usamos o cliente autenticado + fallback com token.
  /// No web, se o URL da miniatura falhar (CORS), usa download pela API (mesmo host).
  Future<Uint8List?> thumbnailBytesForPicker(drive.File f) {
    final id = f.id;
    Future<Uint8List?> load() async {
      final thumb = await _fetchThumbnailBytes(f.thumbnailLink);
      if (thumb != null && thumb.isNotEmpty) return thumb;
      if (kIsWeb && id != null && id.isNotEmpty) {
        final media = await downloadFileBytes(id);
        if (media != null && media.isNotEmpty) return media;
      }
      return null;
    }

    if (id != null && id.isNotEmpty) {
      return _pickerThumbnailCache.putIfAbsent(id, load);
    }
    return load();
  }

  Future<Uint8List?> _fetchThumbnailBytes(String? thumbnailUrl) async {
    if (thumbnailUrl == null || thumbnailUrl.trim().isEmpty) {
      return null;
    }
    final url = thumbnailUrl.trim();
    try {
      final GoogleSignInAuthorizationClient authClient =
          _account?.authorizationClient ??
              GoogleSignIn.instance.authorizationClient;
      final authz = await authClient.authorizeScopes(kGoogleDriveImageScopes);
      final client = authz.authClient(scopes: kGoogleDriveImageScopes);

      var response = await client.get(Uri.parse(url));
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return Uint8List.fromList(response.bodyBytes);
      }

      final token = authz.accessToken;
      final base = Uri.parse(url);
      final withToken = base.replace(
        queryParameters: <String, String>{
          ...base.queryParameters,
          'access_token': token,
        },
      );

      response = await client.get(withToken);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        return Uint8List.fromList(response.bodyBytes);
      }

      final plain = await http.get(withToken);
      if (plain.statusCode == 200 && plain.bodyBytes.isNotEmpty) {
        return plain.bodyBytes;
      }
    } catch (_) {}

    return null;
  }

  Future<drive.DriveApi?> _api() async {
    try {
      final GoogleSignInAuthorizationClient authClient =
          _account?.authorizationClient ??
              GoogleSignIn.instance.authorizationClient;
      final authz = await authClient.authorizeScopes(kGoogleDriveImageScopes);
      final client = authz.authClient(scopes: kGoogleDriveImageScopes);
      return drive.DriveApi(client);
    } catch (_) {
      return null;
    }
  }

  /// Lista arquivos de imagem (MIME image/*) em todo o Drive, mais recentes primeiro.
  Future<List<drive.File>> listImageFiles({int pageSize = 50}) async {
    final api = await _api();
    if (api == null) return [];
    final response = await api.files.list(
      q: "mimeType contains 'image/' and trashed = false",
      $fields: 'files(id,name,mimeType,thumbnailLink,webViewLink,iconLink)',
      pageSize: pageSize,
      orderBy: 'modifiedTime desc',
    );
    return response.files ?? [];
  }

  /// Lista pastas e imagens dentro de [folderId] (use [kGoogleDriveRootId] para Meu Drive).
  ///
  /// [nameContains] filtra por nome (substring), na pasta atual.
  Future<DriveFolderListResult?> listFolderContents(
    String folderId, {
    String? pageToken,
    int pageSize = 50,
    String? nameContains,
  }) async {
    final api = await _api();
    if (api == null) return null;

    final parent = folderId.trim().isEmpty ? kGoogleDriveRootId : folderId;
    final parentQ = "'$parent' in parents and trashed = false";
    final typeQ =
        "(mimeType contains 'image/' or mimeType = '$_folderMime')";
    String q = '$parentQ and $typeQ';
    if (nameContains != null && nameContains.trim().isNotEmpty) {
      final escaped = nameContains.trim().replaceAll("'", r"\'");
      q = "$q and name contains '$escaped'";
    }

    final response = await api.files.list(
      q: q,
      $fields:
          'nextPageToken, files(id,name,mimeType,thumbnailLink,webViewLink,iconLink,modifiedTime)',
      pageSize: pageSize,
      pageToken: pageToken,
      orderBy: 'folder,name_natural',
    );
    return DriveFolderListResult(
      files: response.files ?? [],
      nextPageToken: response.nextPageToken,
    );
  }

  /// Metadados leves (ex.: miniatura) sem baixar o ficheiro completo.
  Future<drive.File?> getFileMetadata(
    String fileId, {
    String fields = 'id,name,mimeType,thumbnailLink,webViewLink',
  }) async {
    final api = await _api();
    if (api == null) return null;
    return api.files.get(
      fileId,
      $fields: fields,
    ) as drive.File?;
  }

  /// Baixa o conteúdo binário do arquivo (para PDF / preview na UI).
  ///
  /// Reutiliza o mesmo [Future] por [fileId] para que [FutureBuilder] nos widgets
  /// não dispare novo download quando o pai faz `setState` (ex.: atualizar preview).
  ///
  /// Falhas (bytes vazios) não ficam em cache para permitir nova tentativa.
  Future<Uint8List?> downloadFileBytes(String fileId) {
    final id = fileId.trim();
    if (id.isEmpty) {
      return Future<Uint8List?>.value(null);
    }
    return _downloadFileBytesCache.putIfAbsent(id, () {
      return _downloadFileBytesImpl(id).then((bytes) {
        if (bytes == null || bytes.isEmpty) {
          _downloadFileBytesCache.remove(id);
        }
        return bytes;
      });
    });
  }

  Future<Uint8List?> _downloadFileBytesImpl(String fileId) async {
    final api = await _api();
    if (api == null) return null;
    final media = await api.files.get(
      fileId,
      downloadOptions: drive.DownloadOptions.fullMedia,
    ) as drive.Media;
    final list = <int>[];
    await for (final chunk in media.stream) {
      list.addAll(chunk);
    }
    return Uint8List.fromList(list);
  }
}

class _WebDriveSignInDialog extends StatefulWidget {
  const _WebDriveSignInDialog();

  @override
  State<_WebDriveSignInDialog> createState() => _WebDriveSignInDialogState();
}

class _WebDriveSignInDialogState extends State<_WebDriveSignInDialog> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = GoogleSignIn.instance.authenticationEvents.listen((event) {
      if (event is GoogleSignInAuthenticationEventSignIn && mounted) {
        Navigator.of(context).pop(event.user);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Entrar com Google'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Use o botão abaixo para autorizar o acesso ao Google Drive.',
            ),
            const SizedBox(height: 16),
            SizedBox(height: 48, child: buildGsiSignInButton()),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}
