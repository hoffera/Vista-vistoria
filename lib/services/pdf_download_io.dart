import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

/// Implementação desktop/mobile para download de PDF
Future<void> gerarDownloadPdf(Uint8List bytes) async {
  // Obter diretório de documentos
  final directory = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final file = File('${directory.path}/vistoria_$timestamp.pdf');

  // Escrever bytes no arquivo
  await file.writeAsBytes(bytes);

  // Abrir o arquivo
  await OpenFilex.open(file.path);
}

