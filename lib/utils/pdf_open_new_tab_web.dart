import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

/// Abre o PDF no visualizador nativo do browser (nova aba), sem descarregar ficheiro.
void openPdfBytesInNewTab(Uint8List bytes) {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  // Liberta o URL após o carregamento; 60s evita revogar antes da aba abrir em redes lentas.
  Timer(const Duration(seconds: 60), () {
    html.Url.revokeObjectUrl(url);
  });
}
