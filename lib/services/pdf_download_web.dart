import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart';

/// Implementação web (JS e Wasm) para download de PDF via `package:web`.
Future<void> gerarDownloadPdf(Uint8List bytes) async {
  final blobParts = [bytes.toJS].toJS;
  final blob = Blob(blobParts);
  final url = URL.createObjectURL(blob);
  final anchor = document.createElement('a') as HTMLAnchorElement;
  anchor.href = url;
  anchor.download = 'vistoria.pdf';
  anchor.click();
  URL.revokeObjectURL(url);
}
